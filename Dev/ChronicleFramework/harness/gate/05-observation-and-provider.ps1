#Requires -Version 7.0

# Observation and provider: observation schema, encounter retreat warning, map incidents, model provider contract.
# Sources asserted here: Test-AgentObservation.ps1, Agent-OpenAICompatibleProvider.ps1, Test-AgentOpenAICompatibleProvider.ps1, AgentHostCampaignStateFacts.cs

$agentObservationTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentObservation.ps1') -Raw -Encoding UTF8
if ($agentObserverSource -notmatch 'nativeConversationReady' -or $agentObserverSource -notmatch 'schemaVersion\\":34' -or $agentObservationTestSource -notmatch '\$snapshot\.schemaVersion -eq 34') {
    throw 'The current observation schema must expose Native MissionConversation readiness and keep its current schema assertion synchronized.'
}
if ($agentObserverSource -notmatch 'encounterEscape' -or $agentObserverSource -notmatch 'BuildEncounterEscapeContextJson' -or
    $agentObserverSource -notmatch 'GetNumberOfTroopsSacrificedForTryingToGetAway' -or
    $agentEncounterEscapeTestSource -notmatch 'NativeEscapeObservation' -or
    $agentEncounterEscapeTestSource -notmatch 'nativeTroopsSacrificedForTry') {
    throw 'The Native encounter retreat warning and TroopSacrificeModel estimate must be visible in the normal Agent observation and checked against the current Native diagnostic.'
}
if ($agentObserverSource -notmatch 'mapIncident' -or $agentProtocolSource -notmatch 'case "incidentSelect"' -or $agentMapIncidentAdapterSource -notmatch 'GetMapView<MapIncidentView>' -or $agentMapIncidentAdapterSource -notmatch 'ExecuteSelect' -or $agentMapIncidentAdapterSource -notmatch 'ExecuteConfirm' -or $agentMapIncidentAdapterSource -notmatch 'internal static bool IsActive' -or $agentProtocolSource -notmatch 'EnsureNoActiveMapIncident' -or $agentHostMapIncidentLoopSource -notmatch 'incidentSelect' -or $agentHostMapIncidentLoopSource -notmatch 'native-command-timeout' -or $agentHostEstablishClanAutonomySource -notmatch 'AgentHostMapIncidentLoop.RunAsync') { throw 'Native Map Incidents must be observed from the active original VM, submitted through its select/confirm handlers, and resolved before EYC planning resumes; ambiguous commits must never replay.' }
if ($agentProtocolSource -notmatch 'EnsureNoActiveMapIncident\("pursuit"\)' -or $agentProtocolSource -notmatch 'EnsureNoActiveMapIncident\("escort"\)' -or $agentProtocolSource -notmatch 'EnsureNoActiveMapIncident\("hold"\)' -or $agentProtocolSource -notmatch 'EnsureNoActiveMapIncident\("settlement movement"\)' -or $agentProtocolSource -notmatch 'EnsureNoActiveMapIncident\("point movement"\)') { throw 'All Native map click-like actions must reject while a current MapIncident modal blocks player input.' }
if ($harnessScript -notmatch "'MapIncidentInputGuard' \{ @\('Preflight', 'Build', 'AgentHostPackage', 'MapIncidentInputGuard'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'MapIncidentInputGuard'" -or
    $agentCliSource -notmatch "'harnessSeedMapIncidentFixture'" -or
    $agentProtocolSource -notmatch 'case "harnessSeedMapIncidentFixture"' -or
    $agentMapIncidentAdapterSource -notmatch 'SeedHarnessFixture' -or
    $mapIncidentInputGuardTestSource -notmatch 'PursueBlockedBeforeNativeMutation' -or
    $mapIncidentInputGuardTestSource -notmatch 'FixtureHashUnchanged' -or
    $mapIncidentInputGuardTestSource -notmatch 'incidentSelect') {
    throw 'The dedicated disposable MapIncident UI regression must block all original map inputs, resolve only through its Native Done handler, preserve the source fixture, and stay out of the default All run.'
}
if ($agentObserverSource -notmatch 'activeGameState is PartyState' -or $agentInquiryAdapterSource -notmatch 'activeState is not PartyState' -or $agentHostNativeInquiryResolutionSource -notmatch 'PartyState' -or $agentHostNativeInquiryResolutionSource -notmatch 'partyScreen' -or $agentHostNativeInquiryResolutionSource -match 'AgentHostHarnessProgressTrace\.RecordDecision' -or $agentHostNativeInquiryResolutionSource -notmatch 'native-inquiry-provider-call-is-logged-once-for-cost-accounting' -or $agentHostBattleSimulationLoopSource -notmatch 'postbattle-native-inquiry' -or $agentHostBattleSimulationLoopSource -notmatch 'parentEycObjectives') { throw 'Postbattle PartyState Yes/No inquiries must be visible with the current loot roster, resolved through the Native Inquiry handler exactly once per provider call, and informed by the current EYC goal/progress.' }
if ($agentObserverSource -notmatch 'activeGameState is PartyState' -or $agentInquiryAdapterSource -notmatch 'activeState is not PartyState' -or $agentHostNativeInquiryResolutionSource -notmatch 'PartyState' -or $agentHostBattleSimulationLoopSource -notmatch 'postbattle-native-inquiry' -or $agentHostBattleSimulationLoopSource -notmatch 'AgentHostNativeInquiryResolution.RunAsync' -or $agentHostBattleSimulationLoopSource -notmatch 'parentEycObjectives') { throw 'Postbattle PartyState Yes/No inquiries must be visible with the current loot roster, resolved through the Native inquiry handler, and informed by the current EYC goals.' }
if ($agentObserverSource -notmatch 'mainAgent\.CanInteractWithAgent\(item\.Agent, mainAgentController\.MissionScreen\.CameraElevation\)' -or
    $agentObserverSource -notmatch 'IsThereAgentAction\(mainAgent, agent\)' -or
    $agentObserverSource -notmatch 'nativeConversationActionAvailable' -or
    $agentObserverSource -notmatch 'schemaVersion\\":2,\\"scope\\":\\"active human Agents instantiated' -or
    $agentHostCompanionLoopSource -notmatch 'ReadBoolean\(candidate, "nativeConversationActionAvailable"\)' -or
    $agentHostCompanionLoopSource -notmatch 'missionNavigateToAgent' -or
    $agentHostCompanionLoopSource -notmatch 'ReadBoolean\(local, "isInteractable"\)') { throw 'Current local Mission agents must report immediate Native dialogue availability; that range/pose-sensitive value may gate Agent.OnUse, but must not remove distant Wanderers from the navigation candidate list.' }
if ($agentObserverSource -notmatch 'Property\(json, "characterName", conversationManager\.OneToOneConversationCharacter\?\.Name\?\.ToString\(\), true\)' -or
    $agentObserverSource -notmatch 'Property\(json, "heroId", conversationManager\.OneToOneConversationHero\?\.StringId, true\)' -or
    $agentObserverSource -notmatch 'Property\(json, "sentenceText", conversationManager\.CurrentSentenceText, true\)') {
    throw 'Native active conversation fields must serialize as comma-delimited JSON properties for both Hero and non-Hero CharacterObject speakers.'
}
if ($agentObserverSource -notmatch 'mapSettlementTargets' -or $agentObserverSource -notmatch 'item.IsActive && item.IsVisible' -or $agentProtocolSource -notmatch 'settlement.IsVisible' -or $agentProtocolSource -notmatch 'GetInteractionDataForMainParty') { throw 'W2-F must expose only native visible Settlement map targets and keep the move adapter constrained to visible, natively navigable targets.' }
if ($agentObserverSource -notmatch 'mainHeroSkills' -or $agentObserverSource -notmatch 'Skills.All' -or $agentObserverSource -notmatch 'hero.GetSkillValue\(skill\)') { throw 'MainHero skills must come from Campaign skill objects and the native Hero.GetSkillValue calculation.' }
if ($agentObserverSource -notmatch 'BuildMapSettlementTargetsJson' -or $agentProtocolSource -notmatch 'case "mapSettlementTargets"' -or $agentDecisionLoopSource -notmatch 'mapSettlementTargets = @\(\)' -or $agentProtocolSource -notmatch 'mapSettlementTargets requires the Campaign Map state') { throw 'Map targets must be exposed as an on-demand read-only Campaign Map observation tool, not repeated in every state snapshot.' }
if ($agentDecisionLoopSource -notmatch 'schemaVersion = 3' -or $agentDecisionLoopSource -notmatch 'goal = \$Goal' -or $agentDecisionLoopSource -notmatch 'recentDecisionHistory = @\(Get-RecentDecisionHistory -Trace \$trace\)' -or $agentDecisionLoopSource -notmatch 'allowedActions = @\(\$actionCatalog' -or $agentDecisionLoopSource -notmatch '\$allowed = \$ActionCatalog' -or $agentDecisionLoopSource -notmatch 'AllowedActionNames' -or $agentDecisionLoopSource -notmatch 'providerStartedUtc' -or $agentDecisionLoopSource -notmatch 'actionCompletedUtc' -or $agentDecisionLoopSource -notmatch 'observationCompletedUtc' -or $agentDecisionTestProviderSource -notmatch 'schemaVersion -ne 3' -or $agentDecisionTestProviderSource -notmatch 'recentDecisionHistory' -or $agentDecisionTestProviderSource -notmatch 'decisionContext' -or $agentDecisionTestProviderSource -notmatch 'exact requested map-action scope' -or $agentDecisionLoopTestSource -notmatch 'AllowedActionNames' -or $agentDecisionLoopTestSource -notmatch 'GoalAndActionCatalogForwarded' -or $agentDecisionLoopTestSource -notmatch 'ScopedActionRejected' -or $agentDecisionLoopTestSource -notmatch 'DynamicActionCatalogRecoveryVerified' -or $agentDecisionLoopTestSource -notmatch 'DecisionTimingCaptured') { throw 'Agent decision request schema v3 must include a bounded recent action/outcome history alongside the current Native observation, goal, prior receipt, action catalog and timings; the bounded executor still validates every current action.' }
if (-not (Test-Path (Join-Path $stageRoot 'Agent-OpenAICompatibleProvider.ps1')) -or -not (Test-Path (Join-Path $stageRoot 'Test-AgentOpenAICompatibleProvider.ps1')) -or $harnessScript -notmatch 'agentModelProviderScript = Join-Path \$stageRoot ''Test-AgentOpenAICompatibleProvider\.ps1''' -or $harnessScript -notmatch 'OpenAI-compatible provider protocol test failed' -or $agentOpenAiProviderSource -notmatch 'CHRONICLE_LLM_BASE_URL' -or $agentOpenAiProviderSource -notmatch 'CHRONICLE_LLM_MODEL' -or $agentOpenAiProviderSource -notmatch 'CHRONICLE_LLM_API_KEY' -or $agentOpenAiProviderSource -notmatch 'response_format' -or $agentOpenAiProviderSource -notmatch 'allowedActions' -or $agentOpenAiProviderSource -match 'Write-Host' -or $agentOpenAiProviderTestSource -notmatch 'RequestGoalForwarded' -or $agentOpenAiProviderTestSource -notmatch 'AuthorizationHeaderSent' -or $agentOpenAiProviderTestSource -notmatch 'ProviderOutputCredentialFree') { throw 'The real-model provider prototype must remain outside the game process, use local-only credentials/config, validate structured decisions, and have a local HTTP protocol test that never substitutes for a live-model run.' }
if ($agentOpenAiProviderSource -notmatch 'max_completion_tokens' -or $agentOpenAiProviderSource -notmatch 'max_tokens' -or $agentOpenAiProviderSource -notmatch 'store = \$false' -or $agentOpenAiProviderSource -notmatch 'endpointBuilder\.Path' -or $agentOpenAiProviderTestSource -notmatch 'BaseUrlResolvedToChatCompletionsPath' -or $agentOpenAiProviderTestSource -notmatch 'TimeoutFailsClosedWithoutCredentialLeak' -or $agentOpenAiProviderTestSource -notmatch 'HttpErrorFailsClosedWithoutCredentialLeak') { throw 'The Provider contract must resolve a configured base URL to the Chat Completions path, use the current completion-token field by default, allow explicit compatibility override, request no model-output storage, and test HTTP error/timeout fail-closed behavior.' }
if ($agentOpenAiProviderTestSource -notmatch 'LocalCompatibleMaxTokensWithoutAuthorization' -or $agentOpenAiProviderTestSource -notmatch 'LocalReasoningEffortForwarded' -or $agentOpenAiProviderTestSource -notmatch 'LocalTemperatureForwarded' -or $agentOpenAiProviderTestSource -notmatch 'LocalReceiptCompacted' -or $agentOpenAiProviderSource -notmatch 'Ordered goal steps are hard preconditions' -or $agentOpenAiProviderSource -notmatch 'mapSettlementTargetsSummary' -or $agentOpenAiProviderSource -notmatch 'recruitOptionsSummary' -or $agentOpenAiProviderSource -notmatch 'stateSummary' -or $agentOpenAiProviderSource -notmatch 'observeAgain' -or $agentOpenAiProviderSource -notmatch '\[System\.Text\.Encoding\]::UTF8\.GetBytes\(\$body\)' -or $agentOpenAiProviderSource -notmatch 'rationaleSource = ''provider-fallback''' -or $agentOpenAiProviderTestSource -notmatch 'UnicodeObservationForwarded' -or $agentOpenAiProviderTestSource -notmatch 'ExactPositionalArgumentsNormalized' -or $agentOpenAiProviderTestSource -notmatch 'BoundedObserveAgainControlValidated' -or $agentOpenAiProviderTestSource -notmatch 'DisallowedActionFailsClosed' -or $agentOpenAiProviderTestSource -notmatch 'HttpErrorFailsClosedWithoutCredentialLeak' -or $agentOpenAiProviderTestSource -notmatch 'TimeoutFailsClosedWithoutCredentialLeak' -or $agentOpenAiProviderTestSource -notmatch 'local HTTP stub; not a real model call') { throw 'Provider contract must test UTF-8 transport, compact map/recruitment receipts, exact argument-tuple normalization, rationale fallback labeling, bounded observeAgain, local no-key operation, and fail-closed errors without claiming live-model coverage.' }
if ($harnessScript -notmatch "'LiveModel' \{ @\('Preflight', 'Build', 'LiveModel'\) \}" -or $harnessScript -notmatch "'LiveModel' \{" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModel'") { throw 'Real model verification must be an explicit, cost-bearing opt-in Harness phase and remain outside All.' }
if ($harnessScript -notmatch "'LiveModelArrival' \{ @\('Preflight', 'Build', 'LiveModelArrival'\) \}" -or $harnessScript -notmatch "'LiveModelArrival' \{" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelArrival'") { throw 'Native arrival verification must be a separate opt-in real-model Harness phase and remain outside All.' }
if ($harnessScript -notmatch "'LiveModelRecruitment' \{ @\('Preflight', 'Build', 'LiveModelRecruitment'\) \}" -or $harnessScript -notmatch "'LiveModelRecruitment' \{" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelRecruitment'") { throw 'Native live-model recruitment verification must be a separate opt-in Harness phase and remain outside All.' }
if ($harnessScript -notmatch "'LiveModelSafePassageRecruitment' \{ @\('Preflight', 'Build', 'LiveModelSafePassageRecruitment'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelSafePassageRecruitment'") { throw 'Roadside Safe Passage integration must be a dedicated opt-in real-model Harness phase outside All.' }
if ($agentLiveModelLoopSource -notmatch 'RoadsideBanditNegotiationLoop' -or $agentLiveModelLoopSource -notmatch 'barterAutoBalance' -or $agentLiveModelLoopSource -notmatch 'SafePassageRoute' -or $agentDecisionLoopSource -notmatch 'HarnessPrepareSafePassageAfterMove' -or $agentDecisionLoopSource -notmatch 'visual Harness run whose decision allowlist includes Native move' -or $agentDecisionLoopSource -notmatch 'native-safe-passage-conversation-observed') { throw 'The real-model Safe Passage scenario must use the current Native dialogue/Barter flow and keep its world-interruption fixture isolated to visual Harness runs.' }
if ($agentLiveModelLoopSource -notmatch 'Get-Process -Name Bannerlord\*' -or $agentLiveModelLoopSource -notmatch 'CHRONICLE_LLM_BASE_URL' -or $agentLiveModelLoopSource -notmatch 'CHRONICLE_LLM_MODEL' -or $agentLiveModelLoopSource -notmatch '\$allowedActions = ''mapSettlementTargets,move''' -or $agentLiveModelLoopSource -notmatch 'Start-ChronicleWindowVideoCapture' -or $agentLiveModelLoopSource -notmatch 'Write-LiveModelCaptureEvent' -or $agentLiveModelLoopSource -notmatch 'LiveModelEngine-before' -or $agentLiveModelLoopSource -notmatch 'LiveModelEngine-after' -or $agentLiveModelLoopSource -notmatch 'LiveModelEngine-failure' -or $agentLiveModelLoopSource -notmatch 'FailureEngineFrameCaptured' -or $agentLiveModelLoopSource -notmatch 'FixtureUnchanged' -or $agentLiveModelLoopSource -notmatch 'QueryThenNativeMoveVerified' -or $agentLiveModelLoopSource -notmatch 'ProcessStopped') { throw 'The opt-in LiveModel phase must refuse an already-running game, require local provider configuration, restrict the model to visible map query/movement, capture the real Bannerlord HWND and engine frames with aligned model/action events, retain failure visuals, verify the Native target receipt, and preserve fixture/process cleanup.' }
if ($agentDecisionLoopSource -notmatch 'Convert-ObservationForDecision' -or $agentDecisionLoopSource -notmatch 'campaign-map-travel' -or $agentDecisionLoopSource -notmatch 'campaign-settlement-recruitment' -or $agentDecisionLoopSource -notmatch 'MaxElapsedSeconds' -or $agentDecisionLoopSource -notmatch 'schedulerWaitElapsedMilliseconds' -or $agentDecisionLoopSource -notmatch 'Get-ObserveAgainPolicy' -or $agentDecisionLoopPolicySource -notmatch 'StoppablePlay' -or $agentDecisionLoopPolicySource -notmatch 'encounterActive' -or $agentDecisionLoopSource -notmatch 'control-unavailable' -or $agentLiveModelLoopSource -notmatch 'ArrivalLoop' -or $agentLiveModelLoopSource -notmatch 'ArrivalConfirmed' -or $agentLiveModelLoopSource -notmatch 'BoundedReobservations' -or $agentLiveModelLoopSource -notmatch 'NativeTravelReobservations' -or $agentLiveModelLoopSource -notmatch 'CampaignDayAdvancedDuringTravel') { throw 'Map travel and settlement recruitment model views must wait only while Native movement and Campaign time are active; stopped encounters must return feedback, and travel acceptance must use fresh Native arrival/time evidence.' }
if ($agentDecisionLoopPolicySource -notmatch 'function Test-UnobstructedCampaignMap' -or $agentDecisionLoopSource -notmatch 'Test-UnobstructedCampaignMap' -or $agentDecisionLoopSource -notmatch 'During a hostile encounter, expose the active conversation/barter route' -or $agentDecisionLoopSource -notmatch 'clickableDialogueOptions' -or $agentDecisionLoopSource -notmatch 'Get-BarterActionGate' -or $agentDecisionLoopSource -notmatch 'banditWaitingForBarterProbe' -or $agentDecisionLoopSource -notmatch 'nativeBarterProbeWasRejected' -or $agentDecisionLoopSource -notmatch 'nativeSafePassageOfferAccepted' -or $agentDecisionLoopSource -notmatch 'priorFeedback' -or $agentDecisionLoopSource -notmatch 'barterOptions' -or $agentDecisionLoopSource -notmatch 'dialogueContinue' -or $agentDecisionLoopTestSource -notmatch 'UnavailableDialogueRejectedWithoutNativeAction' -or $agentDecisionLoopTestSource -notmatch 'MapMovementCatalogRequiresUnobstructedCampaignMap' -or $agentDecisionTestProviderSource -notmatch 'unavailableDialogueRecovery') { throw 'Map movement must be hidden under Native menus/encounters, hostile encounter options must steer through current conversation/Barter, and the guards must retain prior feedback and have deterministic recovery coverage.' }
if ($agentDecisionLoopPolicySource -notmatch 'function Get-EffectiveControlCatalog' -or $agentDecisionLoopSource -notmatch 'Get-EffectiveControlCatalog' -or $agentDecisionLoopSource -notmatch 'allowedControls = \$controlCatalog' -or $agentDecisionLoopTestSource -notmatch 'ObserveAgainControlIsExposedOnlyWhenSafe' -or $agentOpenAiProviderSource -notmatch 'use only controls in `allowedControls`') { throw 'The Agent must expose scheduler controls only when currently safe, instruct the model to follow that catalog, and keep a deterministic regression for encounter/stopped-time states.' }
if ($agentLiveModelLoopSource -notmatch 'RecruitmentLoop' -or $agentLiveModelLoopSource -notmatch 'NativeRecruitmentVerified' -or $agentLiveModelLoopSource -notmatch 'recruit_volunteers' -or $agentLiveModelLoopSource -notmatch 'ConfirmPartySizeWarning' -or $agentLiveModelLoopSource -notmatch 'ArrivalConfirmed' -or $agentLiveModelLoopSource -notmatch 'RoadsideBanditNegotiationLoop' -or $agentLiveModelLoopSource -notmatch 'SafePassageRoute' -or $agentLiveModelLoopSource -notmatch 'barterAutoBalance' -or $agentDecisionLoopSource -notmatch 'HarnessPrepareSafePassageAfterMove') { throw 'Live-model recruitment must prove Native recruitment, while the separate Safe Passage scenario exercises current dialogue/barter recovery using a Harness-only interruption.' }
if ($agentLiveModelLoopSource -notmatch 'nativeReadObservationsAfterMove' -or $agentLiveModelLoopSource -notmatch 'travelReobserved' -or $agentLiveModelLoopSource -notmatch 'currentSettlementId.*chosenId') { throw 'A current Native observation after movement must count when it records either advancing travel or arrival at the target, without requiring a redundant scheduler wait.' }
if ($agentLiveModelLoopSource -notmatch 'ModelId = \[string\]\$env:CHRONICLE_LLM_MODEL' -or $agentLiveModelLoopSource -notmatch 'ModelThinkingMode' -or $agentLiveModelLoopSource -notmatch 'ModelReasoningEffort' -or $agentLiveModelLoopSource -notmatch 'SourceCommit = \$sourceCommit' -or $agentLiveModelLoopSource -notmatch 'SourceTrackedTreeClean' -or $agentLiveModelLoopSource -notmatch 'CampaignDayStart' -or $agentLiveModelLoopSource -notmatch 'CampaignDayEnd') { throw 'A real-model acceptance receipt must identify model, reasoning mode, source commit, tracked-tree state, and Campaign day interval without recording credentials.' }
if ($harnessScript -notmatch "'MultiDaySupplyBaseline' \{ @\('Preflight', 'Build', 'MultiDaySupplyBaseline'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'MultiDaySupplyBaseline'" -or $harnessScript -notmatch 'SupplyBaselineProvisionAmount = 4' -or $harnessScript -notmatch '-ProvisionAmount \$SupplyBaselineProvisionAmount' -or $multiDaySupplyBaselineSource -notmatch 'deterministic Native-action baseline' -or $multiDaySupplyBaselineSource -notmatch 'foodInventory' -or $multiDaySupplyBaselineSource -notmatch 'dailyWage' -or $multiDaySupplyBaselineSource -notmatch 'dailyTickCount' -or $multiDaySupplyBaselineSource -notmatch 'FixtureHashBefore' -or $multiDaySupplyBaselineSource -notmatch 'NoHarnessClockActionsUsed' -or $multiDaySupplyBaselineSource -match "Invoke-AgentCli '(advance|pause|resume|fastForward)'" -or $multiDaySupplyBaselineSource -notmatch "Invoke-AgentCli 'rest'" -or $multiDaySupplyBaselineSource -notmatch "Invoke-AgentCli 'provision'") { throw 'The multi-day supply Native baseline must remain opt-in, use only Native rest/trade/movement, measure resource/time postconditions, and preserve fixture cleanup.' }
if ($subModuleSource -notmatch 'chronicle_agent_campaign_instance_v1' -or $subModuleSource -notmatch 'chronicle_agent_checkpoint_json_v1' -or $subModuleSource -notmatch 'SyncData\(IDataStore dataStore\)' -or $subModuleSource -notmatch 'Checkpoint Campaign identity does not match' -or $agentProtocolSource -notmatch 'case "agentCheckpointGet"' -or $agentProtocolSource -notmatch 'case "agentCheckpointSet"' -or $agentCliSource -notmatch 'agentCheckpointGet' -or $agentCliSource -notmatch 'agentCheckpointSet' -or $agentDecisionLoopSource -notmatch 'ResumeCheckpoint' -or $agentDecisionLoopSource -notmatch 'PersistCheckpoint' -or $agentDecisionLoopSource -notmatch 'provider-stopped' -or $agentCheckpointPersistenceSource -notmatch 'CampaignInstanceStableAcrossNativeSaveLoad' -or $agentCheckpointPersistenceSource -notmatch 'LastMoveReceiptRestored' -or $agentLiveModelResumeSource -notmatch 'ResumeCheckpoint' -or $agentLiveModelResumeSource -notmatch 'GoalRestored' -or $agentLiveModelResumeSource -notmatch 'MoveNotRepeated' -or $agentLiveModelResumeSource -notmatch 'RecruitmentVerified') { throw 'W4 checkpoint recovery must persist a schema-versioned goal/confirmed receipt with Campaign save identity, re-observe after Native load, and verify a real-model resume without repeating the completed move.' }
if ($harnessScript -notmatch "'CheckpointPersistence' \{ @\('Preflight', 'Build', 'CheckpointPersistence'\) \}" -or $harnessScript -notmatch "'LiveModelResume' \{ @\('Preflight', 'Build', 'LiveModelResume'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelResume'") { throw 'Checkpoint round-trip and real-model resume must be separate opt-in Harness phases; real LLM resume must remain outside All.' }
if ($harnessScript -notmatch "'LiveModelRuntimeResume' \{ @\('Preflight', 'Build', 'LiveModelRuntimeResume'\) \}" -or $harnessScript -notmatch "-RuntimeOnlyResume" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelRuntimeResume'") { throw 'Agent-only restart with a still-running Campaign must be a separate opt-in real-model phase outside All.' }
if ($agentLiveModelResumeSource -notmatch 'RuntimeOnlyResume' -or $agentLiveModelResumeSource -notmatch 'BannerlordProcessUnchangedAcrossResume' -or $agentLiveModelResumeSource -notmatch 'RuntimeRunIdChanged') { throw 'LiveModelRuntimeResume must keep the same Bannerlord process while starting a distinct resumed Agent loop.' }
if ($harnessScript -notmatch "'LiveModelActionRecovery' \{ @\('Preflight', 'Build', 'LiveModelActionRecovery'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelActionRecovery'") { throw 'Native action reconciliation after an Agent-only fault must be an explicit opt-in phase outside All.' }
if ($agentDecisionLoopSource -notmatch 'HarnessCrashAfterAction' -or $agentDecisionLoopSource -notmatch 'expectedGoldAfter' -or $agentDecisionLoopSource -notmatch 'expectedMembersAfter' -or $agentDecisionLoopSource -notmatch 'recoveredAfterRuntimeInterruption' -or $agentDecisionLoopSource -notmatch 'Environment\]::Exit\(93\)' -or $agentLiveModelResumeSource -notmatch 'CrashAfterNativeRecruitVerified' -or $agentLiveModelResumeSource -notmatch 'sameSlotStillAvailable' -or $agentLiveModelResumeSource -notmatch '-HarnessCrashAfterAction recruit') { throw 'The post-recruit fault path must verify Native effects from pending intent plus fresh state and refuse a duplicate transaction.' }
if ($agentDecisionLoopSource -notmatch 'HarnessCrashAfterAction' -or $agentDecisionLoopSource -notmatch 'visual-capture' -or $agentDecisionLoopSource -notmatch 'pendingAction' -or $agentDecisionLoopSource -notmatch 'expectedGoldAfter' -or $agentDecisionLoopSource -notmatch 'recoveredAfterRuntimeInterruption' -or $agentDecisionLoopSource -notmatch 'Environment\]::Exit\(93\)' -or $agentLiveModelResumeSource -notmatch 'CrashAfterRecruit' -or $agentLiveModelResumeSource -notmatch 'CrashAfterNativeRecruitVerified') { throw 'The fault path must be Harness-gated, persist a pending Native recruit intent before execution, kill only the decision Runtime after real success, and verify reconciliation without repeating recruit.' }
if ($harnessScript -notmatch "'CheckpointValidation' \{ @\('Preflight', 'Build', 'CheckpointValidation'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'CheckpointValidation'") { throw 'Invalid-checkpoint validation must be an opt-in failure-safety stage outside All.' }
if ($agentProtocolSource -notmatch 'checkpointSchemaVersion != 1 && checkpointSchemaVersion != 2' -or $agentCliSource -notmatch 'Checkpoint schemaVersion 1 or 2' -or $agentProtocolSource -notmatch 'case "harnessSeedAgentCheckpointFailure"' -or $agentProtocolSource -notmatch 'restricted to a visual Harness run' -or $agentDecisionLoopSource -notmatch 'checkpoint is corrupt or unreadable' -or $agentDecisionLoopSource -notmatch 'schema version.*unsupported' -or $agentDecisionLoopSource -notmatch 'different Campaign instance' -or $agentDecisionTestProviderSource -notmatch 'checkpointMustNotCall' -or $agentCheckpointValidationSource -notmatch 'corrupt-json' -or $agentCheckpointValidationSource -notmatch 'unsupported-schema' -or $agentCheckpointValidationSource -notmatch 'wrong-campaign' -or $agentCheckpointValidationSource -notmatch 'ProviderWasNotCalled' -or $agentCheckpointValidationSource -notmatch 'WorldStateUnchanged') { throw 'Invalid/cross-Campaign checkpoint scenarios must stop before the model Provider or any Native write action; only checkpoint schemas 1 and 2 are accepted.' }
if ($harnessScript -notmatch "'RecruitmentBaseline' \{ @\('Preflight', 'Build', 'RecruitmentBaseline'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'RecruitmentBaseline'") { throw 'Repeated recruitment baseline must remain an explicit opt-in evaluation phase outside All.' }
if ($agentEvaluationRecruitmentBaselineSource -notmatch '\$Runs = 5' -or $agentEvaluationRecruitmentBaselineSource -notmatch 'DistinctCampaignSeeds = 1' -or $agentEvaluationRecruitmentBaselineSource -notmatch 'sourceHash' -or $agentEvaluationRecruitmentBaselineSource -notmatch 'WallClockSeconds' -or $agentEvaluationRecruitmentBaselineProviderSource -notmatch 'deterministic' -or $agentEvaluationRecruitmentBaselineProviderSource -notmatch 'recruit_volunteers' -or $agentEvaluationRecruitmentBaselineProviderSource -notmatch "action = 'recruit'") { throw 'W5 baseline must explicitly report five same-seed native runs, deterministic provider semantics, and real recruitment postconditions without claiming cross-seed/model results.' }
if ($harnessScript -notmatch "'LiveModelRecruitmentEvaluation' \{ @\('Preflight', 'Build', 'LiveModelRecruitmentEvaluation'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelRecruitmentEvaluation'") { throw 'Repeated real-model candidate evaluation must be a separate opt-in phase outside All.' }
if ($agentEvaluationLiveModelRecruitmentSource -notmatch '\$Runs = 5' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'WallClockLimitSeconds = 180' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'CampaignDayLimit = 0\.1' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'SuccessfulRuns' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'DistinctCampaignSeeds = 1' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'RecruitmentVerified' -or $agentEvaluationLiveModelRecruitmentSource -notmatch 'VideoRemovedAfterEvidence') { throw 'The W5 same-save real-model candidate stage must enforce the predeclared five-of-five thresholds and keep cross-seed/generalization limits explicit.' }
if ($harnessScript -notmatch "'LiveModelSupplyEvaluation' \{ @\('Preflight', 'Build', 'LiveModelSupplyEvaluation'\) \}" -or $harnessScript -match "'All' \{[^\r\n]*'LiveModelSupplyEvaluation'") { throw 'Multi-day real-model supply evaluation must be a separate opt-in phase outside All.' }
if ($agentLiveModelLoopSource -notmatch 'SupplyManagementLoop' -or
    $agentLiveModelLoopSource -notmatch '\$allowedActions = ''menuSelect,foodOptions,provision,tradeConfirm,rest''' -or
    $agentLiveModelLoopSource -notmatch "CHRONICLE_LLM_MAX_TOKENS = '256'" -or
    $agentLiveModelLoopSource -notmatch 'dailyTickCount -ne 2' -or
    $agentLiveModelLoopSource -notmatch 'Host passively polls Native state' -or
    $agentLiveModelLoopSource -notmatch 'HostRestPollCount' -or
    $agentLiveModelLoopSource -notmatch 'HostWaitLeaveActionCompleted' -or
    $agentLiveModelLoopSource -notmatch 'naturalTicksElapsed -eq 3' -or
    $agentLiveModelLoopSource -notmatch 'Amount -eq 1' -or
    $agentLiveModelLoopSource -notmatch 'tradeEntrySteps.Count -eq 1' -or
    $agentLiveModelLoopSource -notmatch 'tradeCommitSteps.Count -eq 1' -or
    $agentLiveModelLoopSource -notmatch 'Gold -ge 861' -or
    $agentLiveModelLoopSource -notmatch 'DailyTicksElapsed' -or
    $agentLiveModelLoopSource -notmatch 'SupplyVerified' -or
    $agentLiveModelLoopSource -notmatch 'supply-fixture-prepared' -or
    $agentEvaluationLiveModelSupplySource -notmatch '\$Runs = 3' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'WallClockLimitSeconds = 300' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'maxDecisionsPerRun = 24' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'budgetMaxInputTokensPerCall = 10128' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'budgetTotalMaxInputTokens = 202560' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'maxFoodTransactionsPerRun = 1' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'maxFoodUnitsPerRun = 1' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'maxNativeRestRequestsPerRun = 1' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'requiredDailyTicks = 3' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'minFinalFood = 1\.0' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'minFinalGold = 861' -or
    $agentEvaluationLiveModelSupplySource -notmatch 'VideoRemovedAfterEvidence' -or
    $agentLiveModelLoopSource -match "Invoke-AgentCli '((advance)|(pause)|(resume)|(fastForward))'") {
    throw 'The multi-day supply candidate must use a one-unit Native purchase, exactly three natural ticks, passive Host waiting with one current wait_leave action, current Native postconditions, fixed budgets, and no explicit time-control action.'
}
if ($harnessScript -notmatch "'AgentHostCampaignLoopEvaluation' \{ @\('Preflight', 'Build', 'AgentHostCampaignLoopEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostCampaignLoopEvaluation'" -or
    $harnessScript -notmatch 'Test-AgentHostCampaignLoopEvaluation\.ps1' -or
    $agentHostDecisionCycleSource -notmatch 'CampaignSystemPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'DecideCampaignAsync' -or
    $agentHostCampaignLoopSource -notmatch 'mapSettlementTargets' -or
    $agentHostCampaignLoopSource -notmatch 'ExecuteCampaignActionAsync' -or
    $agentHostCampaignLoopSource -notmatch 'BuildControlCatalog\(movingToTarget, targetReached, before\["state"\] as JsonObject\)' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-requires-goal-scope-classification-before-native-actions' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-unsupported-goal-stops-before-native-actions' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-target-query-precedes-move-and-completion' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-does-not-repeat-map-query-after-empty-result' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-self-test-hostile-meeting-does-not-wait' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-offers-no-market-verb-outside-objective-slices' -or
    $agentHostCampaignLoopSource -notmatch 'provider-goal-classification-unavailable' -or
    $agentHostCampaignLoopSource -notmatch 'AgentHostProviderDecisionRecovery.CanRetry' -or
    $agentHostCampaignLoopSource -notmatch 'provider-arguments-invalid-json' -or
    $agentHostCampaignLoopSource -notmatch 'Native move is already active' -or
    $agentHostDecisionCycleSource -notmatch 'When the fresh Native state confirms the move to that selected target is active and observeAgain is listed' -or
    $agentHostDecisionCycleSource -notmatch 'After the Host accepts classification, never emit either classification control again' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-rejects-unobserved-targets-and-clock-actions' -or
    $agentHostCampaignLoopSource -notmatch 'RunTransportSelfTestsAsync' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-runtime-observe-decide-act-observe-arrival' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-runtime-native-timeout-is-not-replayed' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\-ArrivalLoop' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\-AgentHostRuntime' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'CampaignDayAdvancedDuringTravel' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'VideoRemovedAfterEvidence' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'SourceTrackedTreeClean' -or
    $agentLiveModelLoopSource -notmatch 'parentProcessStartTimeUtcTicks' -or $agentLiveModelLoopSource -notmatch 'nativeSessionId' -or
    $agentLiveModelLoopSource -notmatch 'HostReadyMessages' -or
    $agentHostPackageSource -notmatch '--provider-self-test' -or
    $agentHostPackageSource -notmatch 'CampaignLoopSelfTestScenarioCount' -or
    $agentHostPackageSource -notmatch 'BattleSimulationLoopSelfTestScenarioCount' -or
    $agentHostPackageSource -notmatch 'SharedDecisionCycleScenarioCount' -or
    $agentHostPackageSource -notmatch 'SelfTestNativeCommands' -or
    $agentHostProviderSelfTestSource -notmatch 'VerifySharedDecisionCycleAsync\(settings, "mapSettlementTargets", "CampaignSystemPrompt"' -or
    $agentHostProviderSelfTestSource -notmatch 'VerifySharedDecisionCycleAsync\(settings, "foodOptions", "SupplySystemPrompt"') {
    throw 'The Host campaign loop must remain opt-in and prove its bounded Native map-arrival contract, natural time progression, real local-model path, visual evidence and cleanup.'
}
if ($harnessScript -notmatch "'AgentHostVillageToolsQuestEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostVillageToolsQuestEvaluation'\) \}" -or
    -not $harnessScript.Contains("effectiveSmokeTimeoutSeconds = if (`$Phase -in @('FreshStoryModeModelEvaluation','FreshStoryModeNativeInquiryResponseEvaluation','AgentHostVillageToolsQuestEvaluation','AgentHostEstablishClanGoalPlannerEvaluation','AgentHostEstablishClanAutonomyEvaluation','AgentHostCaptivityRecoveryEvaluation','AgentHostEstablishClanGoldSaleEvaluation','AgentHostBattleSimulationEvaluation','AgentHostBattleAndCaptivityEvaluation')) { [Math]::Max(`$SmokeTimeoutSeconds, 240) }") -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostVillageToolsQuestEvaluation'" -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'VerifyQuestInventoryDelta' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-direct-quest-option-unavailable' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-loop-self-test-alternative-only-stop-failed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-allows-native-alternative-explanation-navigation' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-allows-direct-quest-and-reject-but-blocks-alternative-acceptance' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'HasOnlyOutOfScopeIssueOutcomeOptions' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'IsOutOfScopeIssueOutcomeOption' -or
    $agentHostDecisionCycleSource -notmatch 'only opens the Alternative explanation' -or $agentHostDecisionCycleSource -notmatch 'never select issue_offer_player_accept_alternative' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'inventoryVerifiedAfterTurnIn' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'native-quest-and-inventory-observed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-quest-search-overreach' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'tradeCancel' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-active-quest-dialogue-exit-gate-failed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-active-quest-village-exit-gate-failed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-delivery-giver-gate-failed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-return-to-observed-giver-village-failed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-requires-fresh-journal-after-purchase' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-self-test-inventory-verification-survives-marker-disappearance' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'village-tools-policy-gates-done-on-verified-map-including-settlement-menu' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'GetToolsQuestMapTargetType' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-loop-self-test-giver-village-receipt-failed' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-loop-self-test-unknown-origin-fails-closed' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'GetAllowedDialogueOptions' -or $agentHostVillageToolsQuestPolicySource -notmatch 'IsConversationLeaveOption' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-host-routes-classified-goal-through-native-observe-decide-act-loop' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-host-recovers-from-bounded-invalid-actions-in-open-native-dialogue' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-host-recovers-invalid-village-target-with-current-safe-town-ids' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'sameActionRetryAllowed' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'BuildActionPreconditionFeedback' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'The only allowed Host action is dialogueSelect' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'The Native screen shows gold' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-host-maps-visible-click-to-continue-screen-to-dialogueContinue' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'clickableOptionIds' -or
    $agentHostVillageToolsFixturePreparationSource -notmatch 'Get-ToolsIssueMarker' -or
    $agentHostVillageToolsFixturePreparationSource -notmatch "Invoke-NativeCli 'save'" -or
    $agentHostVillageToolsFixturePreparationSource -notmatch 'SourceFixtureUnchanged' -or
    $agentHostVillageToolsFixturePreparationSource -notmatch 'No Quest was injected' -or
    $agentHostDecisionCycleSource -notmatch 'supportedVillageToolsQuestGoal' -or
    $agentHostDecisionCycleSource -notmatch 'Conversation option IDs are argument values, never action names' -or
    $agentHostDecisionCycleSource -notmatch 'BuildVillageToolsQuestSystemPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'RECOVERY DIRECTIVE' -or
    $agentHostDecisionCycleSource -notmatch 'sameActionRetryAllowed explicitly permits correcting its arguments' -or
    $agentHostDecisionCycleSource -notmatch 'You may repeat that action only with corrected arguments from the current catalog' -or
    $agentHostDecisionCycleSource -notmatch '点击继续' -or $agentHostDecisionCycleSource -notmatch 'does not leave the settlement' -or
    $agentHostDecisionCycleSource -notmatch 'intermediate steps' -or
    $agentHostDecisionCycleSource -notmatch 'steps toward that one outcome' -or
    $agentLiveModelLoopSource -notmatch '\[switch\]\$VillageToolsQuestLoop' -or
    $agentLiveModelLoopSource -notmatch 'tradeCancelChanges,barterOptions,barterAutoBalance,barterOffer,barterCancel,inventoryOpen' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'VillageToolsQuest' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'Test-AgentVillageToolsQuestFixturePreparation' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'VillageToolsQuestInventoryDeltaVerified') {
    throw 'The Host village-tools quest path must remain opt-in and verify the current visible quest, native actions and exact pre/post inventory deltas before allowing completion.'
}
if ($harnessScript -notmatch "'AgentHostEstablishClanGoalPlannerEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostEstablishClanGoalPlannerEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostEstablishClanGoalPlannerEvaluation'" -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\-EstablishYourClanGoalPlanner' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'ChronicleW7N-' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'SourceSha256Before' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'plannerSourceHashAfter' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'RuntimeLoadModuleAugment' -or
    $harnessScript -notmatch 'StoryModePlannerSourceSaveName' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$EstablishYourClanGoalPlanner' -or
    $agentHostLiveModelLoopSource -notmatch '-IncludeChronicleFramework' -or
    $agentCliSource -notmatch '\[switch\]\$IncludeChronicleFramework' -or
    $agentCliSource -notmatch 'observedStartupProcessIds' -or
    $agentCliSource -notmatch 'Stop-ChronicleStartupProcessTree' -or
    $agentCliSource -notmatch 'ActiveModules = \$modules' -or
    $agentCliSource -notmatch 'startup-crash-\$\(\$crashCandidate\.Id\)\.json' -or
    $agentCliSource -notmatch 'Unhandled startup exception' -or
    $agentHostLiveModelLoopSource -notmatch 'rebuild_player_clan_storymode_quest' -or
    $agentHostLiveModelLoopSource -notmatch 'timeControlMode -cne ''Stop''' -or
    $agentHostLiveModelLoopSource -notmatch 'EstablishYourClanPlannerVerified' -or
    $agentHostLiveModelLoopSource -notmatch 'storyModeEstablishClanStatus\.status' -or
    $agentHostLiveModelLoopSource -notmatch 'NativeClockActions = @\(\$steps' -or
    $agentHostLiveModelLoopSource -notmatch 'objectiveId' -or
    $agentHostLiveModelLoopSource -notmatch 'FixtureUnchanged = \$fixtureUnchanged') {
    throw 'W7-N must remain opt-in, use a disposable original StoryMode save with the exact naturally active quest, make real decisions through the configured OpenAI-compatible provider, verify four objectives against Journal/native values without gameplay writes, and preserve source/time/world evidence.'
}
if ($agentCliSource -notmatch '\$TimeoutSeconds\s*=\s*\[Math\]::Min\(\$originalTimeoutSeconds,\s*5\)' -or
    $agentCliSource -notmatch 'Stop-AgentProcessTree -RootProcessId \(\[int\]\$session\.processId\)') {
    throw 'Agent-Cli stop must wait only briefly for Native acknowledgement, then always stop the owned Bannerlord process tree and restore Harness-owned files.'
}
if ($harnessScript -notmatch "'AgentHostCaptivityRecoveryEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostCaptivityRecoveryEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostCaptivityRecoveryEvaluation'" -or
    $harnessScript -notmatch 'CaptivityRecoveryFromExisting' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'ChronicleW7O-' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$CaptivityRecoveryLoop' -or
    $agentHostLiveModelLoopSource -notmatch 'isWaitActive' -or
    $agentHostLiveModelLoopSource -notmatch 'CaptivityRecoveryVerified' -or
    $agentHostLiveModelLoopSource -notmatch 'CaptivityRecoveryTargetConsistency' -or
    $agentHostCampaignLoopSource -notmatch 'supportedCaptivityRecoveryGoal' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'ShouldPassivelyWait' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'captivity-recovery-current-menu-unsupported' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'menu_captivity_end_no_more_enemies' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'menu_captivity_end_wilderness_escape' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'menu_captivity_end_propose_ransom_in_prison' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'mno_continue' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'CaptivityRecoveryNativeClient' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'postPlanDocument' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'finalStoryModeEstablishClanStatus' -or
    $agentHostDecisionCycleSource -notmatch 'CaptivityRecoverySystemPrompt' -or
    $agentHostMailboxSource -notmatch 'ExecuteCaptivityRecoveryActionAsync') {
    throw 'W7-O must remain opt-in, resume from an already captive active StoryMode source without starting a battle, separate explicit Play from passive waiting, use only current enabled source-verified captivity menu choices, replan after free-map verification, and clean its disposable copy.'
}
if ($harnessScript -notmatch "'AgentHostEstablishClanGoldSaleEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostEstablishClanGoldSaleEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostEstablishClanGoldSaleEvaluation'" -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\[switch\]\$EstablishClanGoldSaleFromStoryMode' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$EstablishClanGoldSaleLoop' -or
    $agentHostLiveModelLoopSource -notmatch 'EstablishClanGoldSaleVerified' -or
    $agentHostCampaignLoopSource -notmatch 'supportedEstablishClanGoldSaleGoal' -or
    $agentHostGoldSaleLoopSource -notmatch 'nativeTooltipType"\) == "Goods"' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-scoped-prompt-contract-failed' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-whole-stack-sale-rejected' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-oversized-sale-accepted' -or
    $agentHostGoldSaleLoopSource -notmatch 'var sellAmounts = new JsonArray\(1\)' -or
    $agentHostGoldSaleLoopSource -notmatch 'amount > offerStock' -or
    $agentHostGoldSaleLoopSource -notmatch 'BuildProviderPreviousReceipt' -or
    $agentHostGoldSaleLoopSource -notmatch 'currently sellable PlayerInventory Goods' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-provider-trade-receipt-projection-failed' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-provider-trade-receipt-volume-not-reduced' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-empty-trade-cannot-reopen-market' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-empty-trade-exit-prompt-not-scoped' -or
    $agentHostDecisionCycleSource -notmatch 'BuildEstablishClanGoldSaleSystemPrompt' -or
    $agentHostGoldSaleLoopSource -notmatch 'compactTrade\["data"\] = new JsonObject' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-native-commit-unverified' -or
    $agentHostGoldSaleLoopSource -notmatch 'partyScreenCancel' -or $agentHostGoldSaleLoopSource -notmatch 'gold-sale-ransom-cancel-unverified' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-ransom-sale-actions-missing' -or $agentHostCampaignLoopSource -notmatch 'partyScreenCancel' -or $agentHostCampaignLoopSource -notmatch 'sellPrisonerOne' -or
    $agentRansomPrisonerSaleAdapterSource -notmatch 'ExecuteCancelWithoutInquiry' -or $agentRansomPrisonerSaleAdapterSource -notmatch 'partyScreenClosed' -or
    $agentObserverSource -notmatch 'cancelAvailable' -or $agentProtocolSource -notmatch 'case "partyScreenCancel"' -or
    $agentHostRuntimeControllerSource -notmatch 'partyScreenCancel' -or $agentCliSource -notmatch "'partyScreenCancel'" -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-native-move-start-transition-poll-failed' -or
    $agentHostGoldSaleLoopSource -notmatch 'MinimumActiveMapTravelObserveSeconds' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-active-map-observation-cadence-failed' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-existing-native-move-adoption-self-test-failed' -or
    $agentHostGoldSaleLoopSource -notmatch 'ReadExistingNativeSettlementMoveTarget' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-passively-observed-existing-native-move' -or
    $agentHostProviderSource -notmatch 'GetObserveAgainWaitBounds' -or
    $agentHostProviderSelfTestSource -notmatch 'provider-structured-output-enforces-context-specific-active-travel-observe-interval' -or
    $agentHostDecisionCycleSource -notmatch '5-10 second Host-side wait' -or
    $agentHostGoldSaleLoopSource -notmatch 'moveStartPending' -or
    $agentHostDecisionCycleSource -notmatch 'Immediately after your own move, Native may briefly show the selected target before isMoving becomes true' -or
    $agentHostMailboxSource -notmatch 'ValidateGoldSaleAction' -or
    $agentHostMailboxSource -notmatch 'PlayerInventory' -or
    $agentHostMailboxSource -notmatch 'out var amount\) && amount >= 1' -or
    $agentHostGoldSaleLoopSource -notmatch 'var sellAmounts = new JsonArray\(1\)' -or
    $harnessScript -notmatch 'StoryModePlannerSourceSaveName = ''save002''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7P-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'storyModeGoldSaleSourceHashBefore' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'objectiveJournalBefore\.JournalGoldCurrent' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'objectiveJournalAfter\.current' -or
    $agentHostCampaignLoopEvaluationSource -match '\$saleVerification\.journalGoldAfter|\$saleVerification\.journalGoldBefore|\$saleVerification\.journalGoldTarget' -or
    $agentHostLiveModelLoopSource -notmatch 'JournalGoldCurrent' -or
    $agentHostLiveModelLoopSource -notmatch 'EstablishClanGoldSaleVerification') {
    throw 'W7-P must keep native goods/Ransom sales within current observed options, publish only sell quantities its own mailbox will send, expose Native Ransom rollback, isolate campaign goal scope, and preserve source/visual/cleanup evidence.'
}
if ($agentHostCampaignLoopSource -notmatch 'TownTradeActions' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-town-trade-is-a-separate-accepted-buy-profile' -or
    $agentHostDecisionCycleSource -notmatch 'IAgentHostTownTradeNativeClient' -or
    $agentHostMailboxSource -notmatch 'ExecuteTownTradeActionAsync' -or
    $agentHostMailboxSource -notmatch 'ValidateTownTradeAction' -or
    $agentHostMailboxSource -notmatch 'direction == "buy"' -or
    $agentHostMailboxSource -notmatch 'side == "OtherInventory"' -or
    $agentHostMailboxSource -notmatch 'native-town-trade-mailbox-allows-only-buy-quotes-and-bounded-market-navigation' -or
    $agentHostProviderSelfTestSource -notmatch 'RunTownTradeActionContractSelfTests') {
    throw 'The town market buy leg must be a separate accepted Host profile with its own bounded mailbox: buy direction, OtherInventory side, positive amount, and no sale or clock-control verbs.'
}

$agentHostTownTradeLoopPath = Join-Path $agentHostRoot 'AgentHostTownTradeLoop.cs'
if (-not (Test-Path -LiteralPath $agentHostTownTradeLoopPath)) {
    throw 'The town-trade bounded buy loop must live in agenthost/AgentHostTownTradeLoop.cs.'
}
$agentHostTownTradeLoopSource = Get-Content -LiteralPath $agentHostTownTradeLoopPath -Raw
if ($agentHostTownTradeLoopSource -notmatch 'DecideTownTradeAsync' -or
    $agentHostTownTradeLoopSource -notmatch 'TownTradeSystemPrompt' -or
    $agentHostTownTradeLoopSource -notmatch 'direction\s*[!=]=\s*"buy"' -or
    $agentHostTownTradeLoopSource -notmatch '(inventorySide|side)\s*[!=]=\s*"OtherInventory"' -or
    $agentHostTownTradeLoopSource -notmatch '\["direction"\]\s*=\s*"buy"' -or
    $agentHostTownTradeLoopSource -notmatch '\["inventorySide"\]\s*=\s*"OtherInventory"' -or
    $agentHostCampaignLoopSource -notmatch 'supported-town-trade' -or
    $agentHostCampaignLoopSource -notmatch 'SetEquals\(TownTradeActions\)' -or
    $agentHostTownTradeLoopSource -notmatch 'IAgentHostTownTradeNativeClient' -or
    $agentHostTownTradeLoopSource -notmatch 'buyVerified|one-native-buy' -or
    $agentHostTownTradeLoopSource -notmatch 'RunContractSelfTests') {
    throw 'Contract 7.717 requires a runnable bounded town-trade buy loop with its own provider prompt, exact action-profile dispatch, buy-side postconditions, and zero-model self-tests.'
}
if ($agentHostCampaignLoopSource -notmatch 'TournamentActions' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-tournament-is-a-separate-opt-in-profile' -or
    $agentHostDecisionCycleSource -notmatch 'IAgentHostTournamentNativeClient' -or
    $agentHostDecisionCycleSource -notmatch 'supportedTournamentGoal' -or
    $agentHostMailboxSource -notmatch 'ExecuteTournamentActionAsync' -or
    $agentHostMailboxSource -notmatch 'ValidateTournamentAction' -or
    $agentHostMailboxSource -notmatch 'native-tournament-mailbox-allows-only-original-handlers-without-arguments' -or
    $agentHostProviderSelfTestSource -notmatch 'RunTournamentActionContractSelfTests' -or
    $agentHostProviderSelfTestSource -notmatch 'supportedTournamentGoal') {
    throw 'The Arena tournament surface must be a separate opt-in Host profile with a bounded original-handler mailbox and zero-model self-tests; it must never leak into all-supported actions.'
}

$agentHostTournamentLoopPath = Join-Path $agentHostRoot 'AgentHostTournamentLoop.cs'
if (-not (Test-Path -LiteralPath $agentHostTournamentLoopPath)) {
    throw 'The tournament observation loop must live in agenthost/AgentHostTournamentLoop.cs.'
}
$agentHostTournamentLoopSource = Get-Content -LiteralPath $agentHostTournamentLoopPath -Raw
if ($agentHostTournamentLoopSource -notmatch 'DecideTournamentAsync' -or
    $agentHostDecisionCycleSource -notmatch 'TournamentSystemPrompt' -or
    $agentHostTournamentLoopSource -notmatch 'TryReadSettledResult' -or
    $agentHostTournamentLoopSource -notmatch 'playerVictoryVerified' -or
    $agentHostTournamentLoopSource -notmatch 'rewardVerified' -or
    $agentHostCampaignLoopSource -notmatch 'supported-tournament' -or
    $agentHostCampaignLoopSource -notmatch 'SetEquals\(TournamentActions\)' -or
    $agentHostTournamentLoopSource -notmatch 'IAgentHostTournamentNativeClient' -or
    $agentHostTournamentLoopSource -notmatch 'RunContractSelfTests') {
    throw 'Contract 7.718 requires a runnable bounded tournament observation loop with its own provider prompt, exact action-profile dispatch, postcondition that never claims player victory or reward from a skip handler, and zero-model self-tests.'
}
$agentHostLiveModelLoopSource = Get-Content -LiteralPath (Join-Path $stageRoot 'Test-AgentLiveModelLoop.ps1') -Raw -Encoding UTF8
$agentHostRecruitmentSource = Get-Content -LiteralPath (Join-Path $agentHostRoot 'AgentHostEstablishClanRecruitmentLoop.cs') -Raw -Encoding UTF8
if ($agentHostCampaignLoopSource -notmatch 'townTradeProfileOnly' -or
    $agentHostCampaignLoopSource -notmatch 'townTradeProfileOnly: townTradeProfileOnly' -or
    $agentHostCampaignLoopSource -notmatch 'supportedTownTradeGoal' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$TownTradeLoop' -or
    $agentHostLiveModelLoopSource -notmatch "name -ceq 'town-trade'" -or
    $agentHostLiveModelLoopSource -notmatch '\$townTradeVerified' -or
    $agentHostLiveModelLoopSource -notmatch 'town-trade-buy' -or
    $agentHostLiveModelLoopSource -notmatch 'Native town buy did not produce' -or
    $agentHostLiveModelLoopSource -notmatch 'TownTradeVerified' -or
    $agentHostLiveModelLoopSource -notmatch 'TownTradeVerification') {
    throw 'Contract 7.719 requires a town-trade-only goal classification opt-in and a real-model bounded buy slice with Native buy receipt verification, not a hand-copied action set or sell-side assertions.'
}
$agentHostProgramSource = Get-Content -LiteralPath (Join-Path $agentHostRoot 'Program.cs') -Raw -Encoding UTF8
$agentHostProviderContractSelfTestSource = Get-Content -LiteralPath (Join-Path $agentHostRoot 'ProviderContractSelfTest.cs') -Raw -Encoding UTF8
if ($agentHostProgramSource -notmatch 'RecordAuthorizedHarnessCampaignLoopResult' -or
    $agentHostProgramSource -notmatch 'HarnessCampaignLoopResultFileName' -or
    $agentHostProgramSource -notmatch 'CHRONICLE_REPOSITORY_ROOT' -or
    $agentHostProgramSource -notmatch 'Path.Combine\(Path.GetFullPath\(harnessTemp\), HarnessCampaignLoopResultFileName\)' -or
    $agentHostLiveModelLoopSource -notmatch 'AgentHostCampaignLoopResult.json' -or
    $agentHostLiveModelLoopSource -notmatch 'did not publish its full Campaign result' -or
    $agentHostLiveModelLoopSource -notmatch 'did not match its terminal receipt for the current run' -or
    $agentHostProviderContractSelfTestSource -notmatch 'campaign-loop-writes-full-result-to-authorized-harness-temp' -or
    $agentHostProviderContractSelfTestSource -notmatch 'campaign-loop-result-rejects-run-id-mismatch' -or
    $agentHostProviderContractSelfTestSource -notmatch 'campaign-loop-result-rejects-temp-outside-testresults' -or
    $agentHostLiveModelLoopSource -notmatch 'CHRONICLE_REPOSITORY_ROOT = Split-Path -Parent \$PSScriptRoot' -or
    $agentHostLiveModelLoopSource -notmatch 'buyOffer\[0\].inventorySide' -or
    $agentHostLiveModelLoopSource -notmatch 'CHRONICLE_REPOSITORY_ROOT = Split-Path -Parent \$PSScriptRoot[\r\n\s]+\$hostStartInfo') {
    throw 'Contract 7.720 requires a Harness-only full Campaign result file, bound by runId and terminal outcome, so real-model receipt verification sees the complete Native buy trace without weakening the game-facing compact terminal receipt.'
}
if ($agentHostCampaignLoopSource -notmatch 'tournamentProfileOnly' -or
    $agentHostCampaignLoopSource -notmatch 'tournamentProfileOnly: tournamentProfileOnly' -or
    $agentHostCampaignLoopSource -notmatch 'supportedTournamentGoal' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$TournamentLoop' -or
    $agentHostLiveModelLoopSource -notmatch 'name -ceq ''tournament''' -or
    $agentHostLiveModelLoopSource -notmatch '\$tournamentVerified' -or
    $agentHostLiveModelLoopSource -notmatch 'tournament-observation' -or
    $agentHostLiveModelLoopSource -notmatch 'Real-model tournament observation did not reach' -or
    $agentHostLiveModelLoopSource -notmatch 'TournamentVerified' -or
    $agentHostLiveModelLoopSource -notmatch 'TournamentVerification' -or
    $agentHostLiveModelLoopSource -notmatch 'arena_master_sign_up_tournament' -or
    $agentHostLiveModelLoopSource -notmatch 'mno_tournament_event_' -or
    $agentHostLiveModelLoopSource -notmatch 'TournamentSetup.json' -or
    $agentHostTournamentLoopSource -notmatch 'isCurrentMatchActive' -or
    $agentHostTournamentLoopSource -notmatch 'tournament-active-match-skips-even-when-can-join-remains-true' -or
    $agentHostCampaignLoopSource -notmatch 'tournamentProfileOnly && requestedActions.SetEquals\(TournamentActions\)') {
    throw 'Contract 7.721 requires a tournament-only goal classification opt-in and a real-model bounded tournament observation slice that verifies one resolved Native result with only original Arena handlers and no unverified victory or reward.'
}
$agentPathDivergencePath = Join-Path $stageRoot 'Get-AgentPathDivergence.ps1'
if (-not (Test-Path -LiteralPath $agentPathDivergencePath)) {
    throw 'Contract 7.722 requires a zero-model same-start path divergence criterion at harness/Get-AgentPathDivergence.ps1.'
}
$agentPathDivergenceSource = Get-Content -LiteralPath $agentPathDivergencePath -Raw -Encoding UTF8
if ($agentPathDivergenceSource -notmatch 'RunDirectories' -or
    $agentPathDivergenceSource -notmatch 'fixtureHash' -or
    $agentPathDivergenceSource -notmatch 'sourceCommit' -or
    $agentPathDivergenceSource -notmatch 'actionFingerprint' -or
    $agentPathDivergenceSource -notmatch 'diverged' -or
    $agentPathDivergenceSource -notmatch 'Fewer than two runs share the same observable start' -or
    $agentPathDivergenceSource -notmatch 'argumentDiverged' -or
    $agentPathDivergenceSource -notmatch 'Get-DecisionFingerprint') {
    throw 'Contract 7.722 requires divergence to be judged only across runs sharing fixture hash, commit, goal, model and budget, with a full Host receipt, and to refuse a claim when fewer than two comparable runs exist.'
}
if ($agentHostRecruitmentSource -notmatch 'legalTuples' -or
    $agentHostRecruitmentSource -notmatch 'establish-clan-recruitment-catalog-publishes-legal-owner-troop-slot-tuples' -or
    $agentHostDecisionCycleSource -notmatch 'use the legalTuples array') {
    throw 'Contract 7.723 requires the recruitment catalog to publish exact legal ownerId/troopId/slot tuples so a real model cannot combine parallel argument arrays into a nonexistent Native offer.'
}
if ($providerHostSource -notmatch 'BuildExactValueSchema' -or
    $providerHostSource -notmatch 'legalTuples' -or
    $providerHostSource -notmatch '\["anyOf"\] = tupleBranches' -or
    $agentHostProviderSelfTestSource -notmatch 'provider-legal-tuples-constrain-cross-field-recruitment-choices' -or
    $agentHostProviderSelfTestSource -notmatch 'provider-legal-tuples-schema-invalid') {
    throw 'Contract 7.724 requires the structured-output schema to constrain cross-field recruitment choices to complete legal tuples, so a small model cannot pick ownerId and slot from different offers.'
}
if ($harnessScript -notmatch "'AgentHostBattleSimulationEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostBattleSimulationEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostBattleSimulationEvaluation'" -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\-BattleSimulationLoop' -or
    $harnessScript -notmatch 'BattleSimulationSourceSaveName' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\$BattleSourceSaveName' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'Get-AgentSaveModuleIds' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'ChronicleW7L-' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\[IO\.File\]::Copy\(\$battleSourceSavePath, \$battleFixtureSavePath, \$false\)' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'IsByteForByteCopy' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'SourceSha256Before' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'battleSourceHashAfter' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$BattleSimulationLoop' -or
    $agentHostLiveModelLoopSource -notmatch 'visual-battle-fixture' -or
    $agentHostRuntimeControllerSource -notmatch 'useDisposableBattleFixtureProfile' -or
    $agentHostRuntimeControllerSource -notmatch 'CHRONICLE_AGENT_PROFILE_PATH' -or
    $agentHostRuntimeControllerSource -notmatch 'providerConfiguration = useDisposableBattleFixtureProfile' -or
    $subModuleSource -notmatch 'CreateDisposableBattleFixture' -or
    $agentHostLiveModelLoopSource -notmatch 'BattleTargetPreflight\.json' -or
    $agentHostLiveModelLoopSource -notmatch 'ModelInferenceStarted = \$false' -or
    $agentHostRuntimeControllerSource -notmatch 'battleSkip' -or
    $agentHostRuntimeControllerSource -notmatch 'dialogueSelect' -or
    $agentHostBattleSimulationLoopSource -notmatch 'bandit_start_defender_1' -or
    $agentHostBattleSimulationLoopSource -notmatch 'common_encounter_ultimatum' -or
    $agentHostBattleSimulationLoopSource -notmatch 'common_bandit_surrender_declined' -or
    $agentHostBattleSimulationLoopSource -notmatch 'common_encounter_fight' -or
    $agentHostDecisionCycleSource -notmatch 'common_encounter_ultimatum' -or
    $agentHostDecisionCycleSource -notmatch 'common_bandit_surrender_declined' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'everyDialogueChoiceMustMatchCurrentCatalogAndClickableOption' -or
    $agentHostBattleSimulationLoopSource -notmatch 'str_order_attack' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battleSimulation' -or
    $agentHostBattleSimulationLoopSource -notmatch 'nativeReturnToMapVerified' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-provider-recovery-budget-invalid' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-truncated-native-surrender-recovery-failed' -or
    $agentHostBattleSimulationLoopSource -notmatch 'prisoner_wait' -or
    $agentHostBattleSimulationLoopSource -notmatch 'partyTakeAll' -or
    $agentHostBattleSimulationLoopSource -notmatch 'partyLootTransferOne' -or
    $agentHostBattleSimulationLoopSource -notmatch 'argumentPairs' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-loot-single-transfer-current-pair-not-resolvable' -or
    $agentLootPartyTransferSource -notmatch 'PartyCharacterVM.ExecuteTransferSingle' -or
    $agentLootPartyTransferSource -notmatch 'RightPartyPrisonersSizeLimit' -or
    $agentLootPartyTransferSource -notmatch 'Native postbattle Loot PartyState' -or
    $agentProtocolSource -notmatch 'case "partyLootTransferOne"' -or
    $agentCliSource -notmatch "'partyLootTransferOne'" -or
    $agentHostBattleSimulationLoopSource -notmatch 'argumentValues' -or
    $agentHostBattleSimulationLoopSource -notmatch 'members or prisoners' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-loot-type-alias-not-rejected' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-native-leave-not-bounded' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-join-encounter-native-options-not-bounded' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-surrender-without-battle-recovers-before-replanning' -or
    $agentHostDecisionCycleSource -notmatch 'If Native menuId is join_encounter' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-native-leave-postcondition-not-verified' -or
    $agentHostBattleSimulationLoopSource -notmatch 'IsVerifiedMapTerminalAfterNativeEncounterLeave' -or
    $agentHostBattleSimulationLoopSource -notmatch 'native-encounter-left-no-battle' -or
    $agentHostBattleSimulationLoopSource -notmatch 'nativeEncounterLeft: true' -or
    $agentHostDecisionCycleSource -notmatch 'If Send Troops and the enabled healthy-troop Attack Mission fallback are both unavailable, use current Native leave if enabled' -or
    $agentHostDecisionCycleSource -notmatch 'nearby hostile parties may join the same battle' -or
    $agentHostDecisionCycleSource -notmatch 'context.encounterEscape.menuText' -or
    $agentHostBattleSimulationLoopSource -notmatch 'native-try-to-get-away-completed' -or
    $agentHostBattleSimulationLoopSource -notmatch 'playerOutcome' -or
    $agentHostBattleSimulationLoopSource -notmatch '\["providerConfigurationSource"\] = provider\.ConfigurationSource' -or
    $agentHostBattleSimulationLoopSource -notmatch 'ReadString\(result, "providerConfigurationSource"\)' -or
    $agentHostLiveModelLoopSource -notmatch 'PlayerOutcome = \[string\]\$loopTrace\.playerOutcome' -or
    $agentHostLiveModelLoopSource -notmatch 'PlayerCaptiveAtMapReturn = \[bool\]\$loopTrace\.playerCaptiveAtMapReturn' -or
    $agentHostLiveModelLoopSource -notmatch 'NativeMapReturnMenuId = \[string\]\$loopTrace\.nativeMapReturnMenuId' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-native-observe-pursue-send-troops-aftermath-return-and-verify' -or
    $agentHostBattleSimulationLoopSource -notmatch 'mapPartyTargetsQueried' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-native-pursuit-loss-rescans-visible-targets-without-idle-wait' -or
    $agentHostBattleSimulationLoopSource -notmatch 'ShouldPauseForVisibleHostileDecision' -or
    $agentHostBattleSimulationLoopSource -notmatch 'visible-hostile-decision-paused-before-model' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-visible-threat-pause-before-model-failed' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-planning-interrupted-by-native-map-incident' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-map-incident-interrupts-before-model-or-native-actions' -or
    $agentHostMailboxSource -notmatch 'PauseForVisibleHostileDecisionAsync' -or
    $agentHostDecisionCycleSource -notmatch 'Host may independently issue and record a Native Pause') {
    throw 'W7-L must remain opt-in, use the current Native Bandit Fight/Send Troops path, process aftermath, verify outcomes and stop safely when no visible target exists.'
}
if ($harnessScript -notmatch "'AgentHostBattleAndCaptivityEvaluation' \{ @\('Preflight', 'Build', 'Smoke', 'AgentHostPackage', 'AgentHostBattleAndCaptivityEvaluation'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'AgentHostBattleAndCaptivityEvaluation'" -or
    $agentHostCampaignLoopSource -notmatch 'supportedBattleAndCaptivityGoal' -or
    $agentHostDecisionCycleSource -notmatch 'BattleAndCaptivitySystemPrompt' -or
    $agentHostDecisionCycleSource -notmatch 'current Native wilderness ransom menu is visible' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\-BattleAndCaptivityLoop' -or
    $agentHostLiveModelLoopSource -notmatch '\[switch\]\$BattleAndCaptivityLoop' -or
    $agentHostBattleSimulationLoopSource -notmatch 'ShouldPassivelyWaitForCaptivity' -or
    $agentHostBattleSimulationLoopSource -notmatch 'captivityRecoveryVerified' -or
    $agentHostBattleSimulationLoopSource -notmatch 'menu_captivity_end_propose_ransom_wilderness' -or
    $agentHostBattleSimulationLoopSource -notmatch 'captivity_end_ransom_deny' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-captivity-waits-for-native-and-binds-ransom-choice') {
    throw 'W7-M must remain an opt-in real-model continuation from an actual Native battle capture, passively wait without clock actions, and restrict ransom decisions to current enabled Native options.'
}
if ($agentHostCampaignLoopEvaluationSource -notmatch '\[string\]\$CleanupPreparedSaveName' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7K-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7L-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7N-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7O-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'StartsWith\(''ChronicleW7P-''' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'Bannerlord process is running' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'Agent CLI session is active' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'escaped the Harness-owned ChronicleW7K/W7L/W7N/W7O/W7P Game Saves boundary' -or
    $agentHostCampaignLoopEvaluationSource -notmatch '\$staleSession\.saveName' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'Get-Process -Id \$stalePid' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'AgentCliStopOutput' -or
    $agentHostCampaignLoopEvaluationSource -notmatch 'AgentHostStaleFixtureRecovery\.json') {
    throw 'Recovery cleanup may delete only a ChronicleW7K disposable fixture after both Bannerlord and its CLI session are absent, and must stay inside Game Saves.'
}
if ($agentHostDecisionCycleSource -notmatch 'AgentHostHarnessProgressTrace\.RecordDecision' -or
    $agentHostHarnessProgressTraceSource -notmatch 'CHRONICLE_HARNESS_MODE' -or
    $agentHostHarnessProgressTraceSource -notmatch 'visual-capture' -or
    $agentHostHarnessProgressTraceSource -notmatch 'agent-host-lifecycle-test' -or
    $agentHostHarnessProgressTraceSource -notmatch 'lifecycle/selftest-route' -or
    $agentHostHarnessProgressTraceSource -notmatch 'AgentHostProgress\.jsonl' -or
    $agentHostHarnessProgressTraceSource -notmatch 'MaximumBytes' -or
    $agentHostHarnessProgressTraceSource -notmatch 'Rationale is deliberately excluded' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildNativeStateSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'nativeStateBefore' -or
    $agentHostHarnessProgressTraceSource -notmatch 'nativeStateAfter' -or
    $agentHostHarnessProgressTraceSource -notmatch 'conversationCharacterId' -or
    $agentHostHarnessProgressTraceSource -notmatch 'conversationOptions' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildVillagersInNeedStartupSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'host-progress-trace-villagers-conversation-startup-self-test' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildObjectiveSnapshotSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildNativeProgressionContextSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'nativeProgressionContext' -or
    $agentHostHarnessProgressTraceSource -notmatch 'host-progress-trace-progression-context-self-test' -or
    $agentHostHarnessProgressTraceSource -notmatch 'harness-progress-trace-records-dynamic-journal-current-target-met-summary' -or
    $agentHostRecruitmentLoopSource -notmatch 'safe-stop-rejected-with-observe-again-control' -or
    $agentHostRecruitmentLoopSource -notmatch 'The currently issued Native map move is still active' -or
    $agentHostRecruitmentLoopSource -notmatch 'BuildRecruitmentOffersObservation' -or
    $agentHostRecruitmentLoopSource -notmatch 'visibleTargetCount' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-duplicate-map-target-payload' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-duplicate-offer-payload' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-target-projection-retains-redundant-flags' -or
    $agentHostRecruitmentLoopSource -notmatch 'SettlementTargetPageSize' -or
    $agentHostRecruitmentLoopSource -notmatch 'GetRecruitmentSettlementTargetPage' -or
    $agentHostRecruitmentLoopSource -notmatch 'mapSettlementTargetsMore' -or
    $agentHostRecruitmentLoopSource -notmatch 'safeSettlementTargetPage' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-target-pagination-failed' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-pages-complete-safe-settlement-set' -or
    $agentHostHarnessProgressTraceSource -notmatch 'providerHttpStatus' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildRecruitmentOfferSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'harness-progress-trace-reports-only-aggregate-affordable-recruitment-offer-counts' -or
    $agentHostHarnessProgressTraceSource -notmatch 'BuildCompanionNavigationSummary' -or
    $agentHostHarnessProgressTraceSource -notmatch 'harness-progress-trace-reports-only-aggregate-companion-navigation-progress' -or
    $agentHostHarnessProgressTraceSource -notmatch 'value\.TryGetValue<int>\(out var number\)' -or
    $agentHostProviderContractSelfTestSource -notmatch 'AgentHostHarnessProgressTrace\.RunContractSelfTests') {
    throw 'Real Host decisions must be incrementally persisted only in bounded Harness visual-capture/lifecycle modes, including the selected Native argument and route but excluding rationale/raw prompt content.'
}
if (-not (Test-Path -LiteralPath (Join-Path $agentHostRoot 'AgentHostCampaignStateFacts.cs')) -or
    $agentHostCampaignStateFactsSource -notmatch 'IsNativeLocationMenu' -or
    $agentHostCampaignStateFactsSource -notmatch 'IsActiveEncounter' -or
    $agentHostCampaignStateFactsSource -notmatch 'campaign-state-facts-training-field-menu-misclassified' -or
    $agentHostCampaignStateFactsSource -notmatch 'campaign-state-facts-hostile-encounter-misclassified' -or
    $agentHostCompanionLoopSource -notmatch 'establish-clan-companion-training-field-menu-misclassified' -or
    $agentHostCompanionLoopSource -notmatch 'companion-navigation-stall-policy-excludes-only-after-two-no-progress-native-approaches' -or
    $agentHostCompanionLoopSource -notmatch 'MinimumCompanionNavigationProgressDistance = 0.1d' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-training-field-menu-not-exitable' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-failure-receipt-preserves-safe-native-state-summary' -or
    $agentHostRecruitmentLoopSource -notmatch 'establish-clan-recruitment-native-training-field-leave-to-volunteer-to-journal-verification' -or
    $agentHostRecruitmentLoopSource -notmatch '\["failureCode"\] = failureCode' -or
    $agentHostGoldSaleLoopSource -notmatch 'gold-sale-self-test-training-field-menu-not-exitable' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-training-field-menu-not-exitable' -or
    $agentHostBattleSimulationLoopSource -notmatch 'trainingFieldLeave\[0\].*argumentValues' -or
    $agentHostBattleSimulationLoopSource -notmatch 'enabledLeaveIds\.Select' -or
    $agentHostProviderContractSelfTestSource -notmatch 'AgentHostCampaignStateFacts.RunContractSelfTests') {
    throw 'EYC objective subflows must distinguish the verified Native training-field Leave menu from a hostile Party encounter and keep the same leave path out of hostile encounter handling.'
}
if ($agentLiveModelLoopSource -notmatch 'elseif \(\$VillageToolsQuestLoop\)[\s\S]{0,900}Set-LiveModelProviderTimeout 360' -or
    $agentLiveModelLoopSource -notmatch 'elseif \(\$VillageToolsQuestLoop\)[\s\S]{0,900}\$env:CHRONICLE_LLM_MAX_TOKENS = ''1024''') {
    throw 'The real-model Village quest slice must retain the bounded 360-second FreeLLMAPI retry deadline and the empirically increased 1024-token output ceiling required after a 512-token structured response was truncated.'
}
if ($agentLiveModelLoopSource -notmatch 'elseif \(\$VillageToolsQuestLoop\)[\s\S]{0,400}\$maxElapsedSeconds = 7200' -or
    $agentLiveModelLoopSource -notmatch '\$maxDecisions = 160' -or
    $agentHostRuntimeControllerSource -notmatch 'maxDecisions\\":2048,\\"maxElapsedSeconds\\":86400' -or
    $agentHostCampaignLoopSource -notmatch 'maxDecisions is >= 1 and <= MaxCumulativeDecisions' -or
    $agentHostCampaignLoopSource -notmatch 'MaxCumulativeDecisions = 2048' -or
    $agentHostEstablishClanAutonomySource -notmatch 'ReadInt\(request, "maxDecisions", AgentHostCampaignLoop\.MaxCumulativeDecisions\)' -or
    $agentHostBattleSimulationLoopSource -notmatch 'ReadInt\(request, "maxDecisions", AgentHostCampaignLoop\.MaxCumulativeDecisions\)' -or
    $agentHostRecruitmentLoopSource -notmatch 'MaxDecisions = AgentHostCampaignLoop\.MaxCumulativeDecisions' -or
    $agentHostCompanionLoopSource -notmatch 'MaxDecisions = AgentHostCampaignLoop\.MaxCumulativeDecisions' -or
    $agentHostGoldSaleLoopSource -notmatch 'for \(var iteration = 1; ledger\.Decisions < maxDecisions; iteration\+\+\)' -or
    $agentHostCaptivityRecoveryLoopSource -notmatch 'for \(var loopIndex = 1; ledger\.Decisions < maxDecisions; loopIndex\+\+\)' -or
    $agentHostCampaignLoopSource -notmatch 'GetCumulativeDecisionLimit\(maxDecisions\)' -or
    $agentHostCampaignLoopSource -notmatch 'campaign-loop-self-test-child-decision-limit-shrank' -or
    $agentHostCampaignLoopSource -notmatch 'maxElapsedSeconds is >= 1 and <= 86400' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'Math\.Clamp\(ReadInt\(request, "maxElapsedSeconds", 86400\), 1, 86400\)' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'Math\.Clamp\(ReadInt\(request, "maxDecisions", 160\), 1, 160\)') {
    throw 'The EYC Host request and all nested objective loops must share the 86400-second/2048-decision cumulative ceiling; separate loops must not restart the full decision allowance when prior decisions are carried forward.'
}
if ($agentHostEstablishClanAutonomySource -notmatch 'AgentHostBattleSimulationLoop\.RunAsync\([\s\S]{0,200}provider, ledger,[\s\S]{0,120}recoverPlayerCaptivity: true' -or
    $agentHostBattleSimulationLoopSource -notmatch 'allowedSurrenderFallback = recoverPlayerCaptivity && !sendTroopsEnabled' -or
    $agentHostBattleSimulationLoopSource -notmatch 'surrender only as a survival fallback' -or
    $agentHostDecisionCycleSource -notmatch 'Never choose surrender in the ordinary Renown BattleSimulation route') {
    throw 'Only an approved incidental encounter in Captivity-recovery mode may use current Native surrender after Send Troops and Leave are disabled; ordinary Renown Simulation must remain separate.'
}
if ($agentHostCampaignLoopSource -notmatch 'TrainingIssueSkipReason\(sale\["finalNativeState"\] as JsonObject, maxDecisions - runLedger\.Decisions\)' -or
    $agentHostCampaignLoopSource -notmatch 'no-reachable-training-issue' -or
    $agentHostCampaignLoopSource -notmatch 'training-issue-discovery-longer-than-remaining-budget' -or
    $agentHostCampaignLoopSource -notmatch '\["skippedReason"\] = trainingSkipReason' -or
    $agentHostTrainingIssueLoopSource -notmatch 'gold-objective-skips-training-issue-discovery-unless-a-giver-is-visible-and-the-remaining-budget-covers-its-search' -or
    $agentHostTrainingIssueLoopSource -notmatch 'HasReachableTrainingIssue\(JsonObject\? native\)' -or
    $agentHostTrainingIssueLoopSource -notmatch 'GetVisibleAvailableTrainingIssueGivers\(state\)\.Length > 0') {
    throw 'The Gold objective may enter the retainers-training Issue route only when a training Issue is already reachable and the remaining Campaign budget can cover its bounded discovery; the battle-loot fallback that can supply goods must keep the budget (TestResults/20261126-live-host-opening4 spent a whole run in training discovery).'
}
if ($agentHostEstablishClanAutonomySource -notmatch 'failed-objective-native-actions-reopened-other-routes' -or
    $agentHostEstablishClanAutonomySource -notmatch 'HasObjectiveSnapshotProgressChanged\(snapshot, child\["objectiveSnapshot"\] as JsonObject\)' -or
    $agentHostEstablishClanAutonomySource -notmatch 'BuildObjectiveRouteAvailabilityFingerprint' -or
    $agentHostEstablishClanAutonomySource -notmatch 'objective-route-reopened-after-native-state-change' -or
    $agentHostEstablishClanAutonomySource -notmatch 'objective-route-retry-after-partial-journal-progress') {
    throw 'A failed EYC subgoal with authoritative Journal progress must remain eligible for another attempt; route blocks must not survive real partial progress.'
}
if ($agentLiveModelLoopSource -notmatch 'Get-FreeLLMAPIModelExecutionStatus -ModelRows @\(\$availableModelsResponse\.data\)' -or
    $agentLiveModelLoopSource -notmatch 'if \(\$modelExecutionStatus -eq ''not-listed''\)' -or
    $agentLiveModelLoopSource -match '\[string\]\$env:CHRONICLE_LLM_MODEL -notin \$availableModelIds' -or
    $agentLiveModelLoopSource -notmatch 'modelExecutionStatus -eq ''router''' -or
    $agentHostProviderSmokeSource -notmatch 'freeLlmApiProfile\.ModelExecutionStatus -eq ''router''' -or
    $agentHostProviderSmokeSource.IndexOf('if ($HealthOnly)', [StringComparison]::Ordinal) -gt $agentHostProviderSmokeSource.IndexOf('if ($freeLlmApiProfile -and $freeLlmApiProfile.ModelExecutionStatus -eq ''router'')', [StringComparison]::Ordinal) -or
    $harnessScript -notmatch 'FreeLLMAPI multi-provider router inference is blocked until its active chain is verified free-only' -or
    $freeLlmApiProfileSource -notmatch 'ModelId -ceq ''free-router''') {
    throw 'Live-model Harness must block unverified FreeLLMAPI automatic/fusion/free-router inference, while retaining zero-call health-only inspection and allowing direct routes to pass through current execution checks.'
}
$eycAutonomyLoopIndex = $agentLiveModelLoopSource.IndexOf('elseif ($EstablishYourClanAutonomyLoop)', [StringComparison]::Ordinal)
$eycAutonomyLoopSource = if ($eycAutonomyLoopIndex -ge 0) { $agentLiveModelLoopSource.Substring($eycAutonomyLoopIndex, [Math]::Min(2500, $agentLiveModelLoopSource.Length - $eycAutonomyLoopIndex)) } else { '' }
if ($eycAutonomyLoopSource -notmatch "CHRONICLE_LLM_MAX_TOKENS = '256'" -or
    $agentHostProviderSource -notmatch 'ReadIntegerEnvironment\("CHRONICLE_LLM_MAX_TOKENS", 256, 64, 4096\)') {
    throw 'The real EYC Harness must use the player MCM Host 256-token default so per-call cost reservation matches product settings and does not fail early on a test-only output cap.'
}
if ($agentActionLoopSource -notmatch 'function Get-EffectiveActionCatalog' -or $agentActionLoopSource -notmatch 'recruit_volunteers' -or $agentActionLoopSource -notmatch 'rejected-before-native' -or $agentActionLoopSource -notmatch 'control-unavailable' -or $agentActionLoopSource -notmatch 'control-rejected-before-native' -or $nativeRejectedActionBranch -match '\$previousActionReceipt\s*=\s*\$actionResult' -or $nativeRejectedActionBranch -notmatch 'Keep the last completed Native receipt available' -or $agentDecisionLoopPolicySource -notmatch 'StoppablePlay' -or $agentDecisionLoopPolicySource -notmatch 'encounterActive' -or $agentDecisionLoopPolicySource -notmatch 'town_wait_menus' -or $agentDecisionLoopSource -notmatch 'Convert-ReceiptForDecision' -or $agentDecisionLoopSource -notmatch 'consecutiveDecisionRejections' -or $agentDecisionLoopSource -notmatch 'decisionRejected' -or $agentOpenAiProviderSource -notmatch 'decisionRejected' -or $agentOpenAiProviderSource -notmatch 'decisionFeedback' -or $agentOpenAiProviderTestSource -notmatch 'invalidActionDecision\.decisionRejected' -or $agentEvaluationRecruitmentBaselineProviderSource -notmatch 'recruitment actions leaked' -or $agentDecisionTestProviderSource -notmatch 'staleOfferRecovery' -or $agentDecisionTestProviderSource -notmatch 'unlistedResumeRecovery' -or $agentDecisionLoopTestSource -notmatch 'ObserveAgainPolicySeparatesNaturalTimeFromStoppedEncounter' -or $agentDecisionLoopTestSource -notmatch 'ObserveAgainCanMonitorAcceptedNativeTownWait' -or $agentDecisionLoopTestSource -notmatch 'StaleOfferRecoveryVerified' -or $agentDecisionLoopTestSource -notmatch 'StaleOfferBlockedWithoutNativeMutation' -or $agentDecisionLoopTestSource -notmatch 'UnlistedResumeRejectedWithoutNativeAction' -or $agentDecisionLoopTestSource -notmatch 'StaleObserveAgainRejectedWithoutNativeAction') { throw 'The Agent decision catalog must respect current Native entries, keep the last successful receipt after rejection, permit bounded observation of accepted Native Town Wait, reject waits while time is stopped/encountered, and bound recovery without Native mutation.' }
if ($agentHostVillageToolsQuestPolicySource -notmatch 'QuoteMatchesBalancedDraft' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'proposalFingerprint' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'GetToolsTaskRemainingCount' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'inventoryLogicUnitPrice' -or
    $agentHostVillageToolsQuestPolicySource -notmatch 'argumentValues' -or
    $agentHostDecisionCycleSource -notmatch 'never repeat Continue' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'safePassageBalanceReceipt' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'village-tools-host-resolves-bandit-interruption-through-native-safe-passage-and-click-to-continue-without-fight-or-clock-actions' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'safe-passage-self-test-unexpected-continue' -or
    $agentHostVillageToolsQuestLoopSource -notmatch 'questDetailsObservedForActiveQuest = false' -or
    $agentHostProviderSelfTestSource -notmatch 'decision-schema-constrains-current-native-string-and-integer-values' -or
    $agentHostProviderSelfTestSource -notmatch 'provider-decision-schema-uses-strict-compatible-root-wrapper' -or
    $barterAdapterSource -notmatch 'BuildProposalFingerprint' -or
    $barterAdapterSource -notmatch 'expectedSessionId' -or
    $agentProtocolSource -notmatch 'expectedProposalFingerprint' -or
    $agentCliSource -notmatch 'ExpectedProposalFingerprint' -or
    $barterContextsSource -notmatch 'NativeOfferRejectsStaleSessionAndProposalWithoutWorldChange') {
    throw 'W7-K Safe Passage Offer must bind the final Native transaction to the same observed BarterVM session and proposal, with stale-session/fingerprint runtime coverage.'
}
if (-not $agentHostRuntimeControllerSource.Contains('\"barterOptions\"') -or
    -not $agentHostRuntimeControllerSource.Contains('\"barterAutoBalance\"') -or
    -not $agentHostRuntimeControllerSource.Contains('\"barterOffer\"') -or
    -not $agentHostRuntimeControllerSource.Contains('\"barterCancel\"')) {
    throw 'The in-game Host start request must pass the same bounded action set that the campaign loop validates.'
}
if ($agentObserverSource -notmatch 'mainHeroSkills' -or $agentObserverSource -notmatch 'Skills.All' -or $agentObserverSource -notmatch 'hero.GetSkillValue\(skill\)') { throw 'MainHero skill observation must use the current Campaign SkillObject collection and native Hero.GetSkillValue without mutating development data.' }
if ($agentProtocolSource -notmatch 'case "harnessPlayerSkillsDiagnostics"' -or $agentProtocolSource -notmatch 'harnessPlayerSkillsDiagnostics is restricted to a visual Harness run' -or $agentDecisionLoopSource -match 'harnessPlayerSkillsDiagnostics') { throw 'Native skill cross-check diagnostics must remain Harness-only and never enter the Agent action allowlist.' }
if ($agentObserverSource -notmatch 'BuildCharacterDevelopmentJson' -or $agentProtocolSource -notmatch 'case "characterDevelopment"' -or $agentCliSource -notmatch "'characterDevelopment'" -or $agentDecisionLoopSource -notmatch 'characterDevelopment = @\(\)' -or $agentProtocolSource -notmatch 'harnessCharacterDevelopmentDiagnostics is restricted to a visual Harness run' -or $agentDecisionLoopSource -match 'harnessCharacterDevelopmentDiagnostics') { throw 'Character development must be an on-demand read-only tool; its native view-model diagnostics must remain Harness-only.' }
if ($agentProtocolSource -notmatch 'case "spendSkillFocus"' -or $agentProtocolSource -notmatch 'SpendMainHeroSkillFocus' -or $agentProtocolSource -notmatch 'exceeds the native maximum Focus' -or $agentProtocolSource -notmatch 'exceeds MainHero''s unspent Focus points' -or $agentCliSource -notmatch "'spendSkillFocus'" -or $agentDecisionLoopSource -notmatch "spendSkillFocus = @\('SkillId','Count'\)") { throw 'Skill Focus investment must validate the whole native Character Developer transaction and remain a bounded Agent action.' }
if ($agentObserverSource -notmatch 'BuildQuestDetailsJson' -or $agentObserverSource -notmatch 'BuildQuestTerminalOutcomeJson' -or $agentObserverSource -notmatch 'terminalStatus' -or $agentObserverSource -notmatch 'IsRemainingTimeHidden' -or $agentObserverSource -notmatch 'JournalEntries' -or $agentProtocolSource -notmatch 'case "questDetails"' -or $agentProtocolSource -notmatch 'FindObservedOngoingQuest' -or $agentProtocolSource -notmatch 'FindQuestTerminalOutcomeJson' -or $subModuleSource -notmatch 'OnQuestCompletedEvent.AddNonSerializedListener' -or $subModuleSource -notmatch 'OnQuestCompleted\(' -or $subModuleSource -notmatch 'chronicle_quest_terminal_outcomes_v1' -or $agentCliSource -notmatch "'questDetails'" -or $agentDecisionLoopSource -notmatch "questDetails = @\('QuestId'\)" -or $agentHostDecisionCycleSource -notmatch 'terminalStatus=Success' -or $agentProtocolSource -notmatch 'harnessQuestDetailsDiagnostics is restricted to a visual Harness run' -or $agentProtocolSource -notmatch 'harnessQuestDeadlinePrivacyDiagnostics is restricted to a visual Harness run' -or $agentDecisionLoopSource -match 'harnessQuestDetailsDiagnostics|harnessQuestDeadlinePrivacyDiagnostics') { throw 'Quest Journal reads must support active details and event-backed terminal outcomes, preserve hidden deadlines, and keep diagnostics Harness-only.' }
if ($agentObserverSource -notmatch 'BuildPartyRosterJson' -or $agentObserverSource -notmatch 'MemberRoster' -or $agentObserverSource -notmatch 'PrisonRoster' -or $agentProtocolSource -notmatch 'case "partyRoster"' -or $agentProtocolSource -notmatch 'harnessPartyRosterDiagnostics is restricted to a visual Harness run' -or $agentCliSource -notmatch "'partyRoster'" -or $agentDecisionLoopSource -notmatch 'partyRoster = @\(\)' -or $agentDecisionLoopSource -match 'harnessPartyRosterDiagnostics') { throw 'MainParty rosters must be an on-demand read-only query with isolated Harness comparison only.' }
if ($agentCliSource -notmatch "'mapSettlementTargets'" -or $agentDecisionLoopSource -notmatch 'mapSettlementTargets = @\(\)' -or $agentProtocolSource -notmatch 'settlement.IsVisible') { throw 'The on-demand map target query must be callable by the agent and the movement adapter must reject hidden settlement IDs.' }
