#Requires -Version 7.0

# Mission input and development docs: mission input patches, village work, save metadata, context focus routing.
# Sources asserted here: AgentMissionInputPatch.cs, Test-AgentVillageToolsProvider.ps1, Test-AgentVillageToolsDelivery.ps1, Agent-SaveMetadata.ps1, Test-AgentSaveMetadata.ps1, HarnessStartupEvidence.ps1, Set-ContextFocus.ps1, HarnessResearchReadiness.ps1, ChronicleFramework.csproj, DEVELOPMENT.md, DESIGN.md, SYSTEM_INVENTORY.md, AGENTS.md, ContextState.json, Get-FreeLLMAPIProfile.ps1, Initialize-ChronicleWorkspace.ps1

$missionInputPatchSource = Get-Content (Join-Path $modRoot 'AgentMissionInputPatch.cs') -Raw -Encoding UTF8
if ($missionInputPatchSource -notmatch 'MissionMainAgentController' -or $missionInputPatchSource -notmatch 'ControlTick' -or $missionInputPatchSource -notmatch 'AfterNativeControlTick') { throw 'Mission movement input must be applied after the native player-axis handler, not by a one-shot setter that the handler immediately overwrites.' }
if ($agentCliSource -notmatch "'missionSceneAgents'" -or $agentProtocolSource -notmatch 'case "missionSceneAgents"' -or $agentObserverSource -notmatch 'BuildMissionSceneAgentsJson' -or $agentDecisionLoopSource -notmatch 'missionSceneAgents = @\(\)' -or $agentCliSource -notmatch "'missionNavigateToAgent'" -or $agentProtocolSource -notmatch 'case "missionNavigateToAgent"' -or $agentProtocolSource -notmatch 'SandBox.AgentNavigator' -or $agentProtocolSource -notmatch 'SetTargetFrame' -or $agentProtocolSource -notmatch 'DoesPathExistBetweenPositions' -or $agentProtocolSource -notmatch 'UpdateMissionNavigationLease' -or $agentProtocolSource -notmatch 'MissionSceneAgentsObservationLeaseSeconds' -or $agentProtocolSource -notmatch 'ReferenceEquals\(observedNavigationTarget, navigationTargetAgent\)' -or $agentProtocolSource -notmatch 'requestedNavigationSeconds' -or $agentDecisionLoopSource -notmatch "missionNavigateToAgent = @\('AgentIndex','DurationSeconds'\)" -or $agentObserverSource -notmatch 'missionNavigationObservationJson') { throw 'Mission scene roster must be explicitly queried for the current friendly Location Mission; remote approach must use a fresh same-Mission observation and native bounded NavMesh navigation, not hidden diagnostics or teleport.' }
if ($agentObserverSource -notmatch 'CurrentFocusedObject' -or $agentObserverSource -notmatch 'nativeFocus') { throw 'Tavern Mission observations must read the active native MainAgent focus rather than guess which scene character is available to interact with.' }
if ($agentCliSource -notmatch "'harnessMissionDiagnostics'" -or $agentCliSource -notmatch "Invoke-ProtocolCommand 'harnessMissionDiagnostics'" -or $agentProtocolSource -notmatch 'case "harnessMissionDiagnostics"' -or $agentProtocolSource -notmatch 'restricted to a visual Harness run' -or $agentProtocolSource -notmatch 'issueNotableCount' -or $agentProtocolSource -notmatch 'locationIssueOwnerCount' -or $agentProtocolSource -notmatch 'CampaignMission.Current' -or $agentProtocolSource -notmatch 'notableAgents' -or $agentDecisionLoopSource -match 'harnessMissionDiagnostics' -or $townCenterMissionSource -notmatch 'diagnostics-only-classified-entry' -or $townCenterMissionSource -notmatch 'outside the Agent local observation radius') { throw 'Full Mission/Location Issue-owner diagnostics must be Harness-only, preserve the roster-vs-spawn distinction, and avoid blind walking when the issue owner is outside local observation.' }
if (-not $agentCliSource.Contains('heroId = $HeroId') -or $agentProtocolSource -notmatch 'case "harnessMapDiagnostics"' -or $agentProtocolSource -notmatch 'restricted to a visual Harness run' -or $agentProtocolSource -notmatch 'sameTypeIssues' -or $agentProtocolSource -notmatch 'isSolvingWithQuest' -or $agentProtocolSource -notmatch 'atWarWithPlayerFaction' -or $agentDecisionLoopSource -match 'harnessMapDiagnostics') { throw 'Settlement diagnostics must expose the targeted Native Issue gate facts only through the visual Harness path, never the model action catalog.' }
if ($agentCliSource -notmatch "'mapSettlementTargets'" -or $agentProtocolSource -notmatch 'case "mapSettlementTargets"' -or $agentObserverSource -notmatch 'BuildMapSettlementTargetsJson' -or $agentDecisionLoopSource -notmatch 'mapSettlementTargets = @\(\)') { throw 'The full visible map-target list must be a separate on-demand observation query, not repeated in every state snapshot.' }
if ($agentObserverSource -notmatch 'settlementOverlayCharacters' -or $agentObserverSource -notmatch 'WillBeListedInOverlay' -or $agentObserverSource -notmatch 'GetQuestStateOfHero' -or $agentObserverSource -notmatch 'OneToOneConversationHero' -or $agentCliSource -notmatch "'talkToSettlementHero'" -or $agentDecisionLoopSource -notmatch "talkToSettlementHero = @\('HeroId'\)" -or $agentProtocolSource -notmatch 'SettlementOverlayTalkPermissionEvent' -or $agentProtocolSource -notmatch 'SettlementOverylayQuickTalkPermissionEvent' -or $agentProtocolSource -notmatch 'OnPlayerStartTalkFromMenu' -or $agentProtocolSource -notmatch 'CampaignMapConversation.OpenConversation' -or $agentProtocolSource -notmatch 'talkToSettlementHero' -or $agentProtocolSource -notmatch 'visitSettlementHero') { throw 'The settlement overlay route must expose only its native visible character list and reproduce the separate QuickConversation and Conversation paths.' }
if ($agentCliSource -notmatch "'missionNavigateToAgent'" -or $agentCliSource -notmatch "'missionCancelNavigation'" -or $agentProtocolSource -notmatch 'case "missionNavigateToAgent"' -or $agentProtocolSource -notmatch 'case "missionCancelNavigation"' -or $agentProtocolSource -notmatch 'requestedNavigationSeconds' -or $agentProtocolSource -notmatch 'Controller = AgentControllerType.AI' -or $agentProtocolSource -notmatch 'AgentControllerType.Player' -or $agentProtocolSource -notmatch 'SetTargetFrame' -or $agentProtocolSource -notmatch 'ClearTarget\(\)' -or $agentDecisionLoopSource -notmatch "missionNavigateToAgent = @\('AgentIndex','DurationSeconds'\)" -or $agentDecisionLoopSource -notmatch 'missionCancelNavigation' -or $agentProtocolSource -notmatch 'remote missionNavigateToAgent target requires a recent missionSceneAgents observation') { throw 'Native AgentNavigator handoff must use a bounded duration, target an observed current-Mission Agent, require a fresh same-Mission scene query for remote targets, and restore Player control.' }
if ($agentCliSource -notmatch "'missionAimAt'" -or $agentProtocolSource -notmatch 'case "missionAimAt"' -or $agentDecisionLoopSource -notmatch "missionAimAt = @\('AgentIndex'\)" -or $agentObserverSource -notmatch 'CameraBearing' -or $agentObserverSource -notmatch 'CameraElevation' -or $agentObserverSource -notmatch 'nearbySceneAgents') { throw 'Location Mission camera aiming must use a locally observed live Agent index and reobserve native focus rather than inject a target.' }
if ($agentProtocolSource -match 'var (quickTalkData|visitData) = [^\r\n]*(hasIssue|issueType|RequestedItem|numberOfRequested|locationId)' -or $agentProtocolSource -notmatch 'var quickTalkData = .*heroName' -or $agentProtocolSource -notmatch 'var visitData = .*heroName') { throw 'QuickTalk and Visit receipts may echo only the observed target identity; private Quest/Issue subtype data must not leak to the AI.' }
$villageToolsProviderSource = Get-Content (Join-Path $stageRoot 'Test-AgentVillageToolsProvider.ps1') -Raw -Encoding UTF8
$villageToolsTestSource = Get-Content (Join-Path $stageRoot 'Test-AgentVillageToolsDelivery.ps1') -Raw -Encoding UTF8
$villageToolsContractFailures = [System.Collections.Generic.List[string]]::new()
if ($harnessScript -notmatch "'VillageToolsDelivery' \{ @\('Preflight', 'Build', 'VillageToolsDelivery'\) \}") { $villageToolsContractFailures.Add('phase-map') }
if ($harnessScript -notmatch "Invoke-Stage -Name 'VillageToolsDelivery'") { $villageToolsContractFailures.Add('stage') }
if ($villageToolsProviderSource -notmatch 'settlementOverlayCharacters' -or $villageToolsProviderSource -notmatch 'AvailableIssue') { $villageToolsContractFailures.Add('visible-issue-marker') }
if ($villageToolsProviderSource -notmatch 'talkToSettlementHero' -or $villageToolsProviderSource -notmatch 'tradeOptions' -or $villageToolsProviderSource -notmatch 'questDetails') { $villageToolsContractFailures.Add('quick-talk-and-native-primitives') }
if ($villageToolsProviderSource -match 'VillageNeedsToolsIssueQuest|FinishQuestSuccess1|CompleteQuestWithSuccess') { $villageToolsContractFailures.Add('private-quest-helper-leak') }
if ($villageToolsTestSource -notmatch 'Agent-DecisionLoop.ps1' -or $villageToolsTestSource -notmatch 'SourceFixtureUnchanged' -or $villageToolsTestSource -notmatch 'ProcessStopped') { $villageToolsContractFailures.Add('loop-or-cleanup') }
if ($villageToolsContractFailures.Count -gt 0) { throw "Village Tools delivery contract failed: $($villageToolsContractFailures -join ', ')." }
$saveModuleMetadataSource = Get-Content (Join-Path $stageRoot 'Agent-SaveMetadata.ps1') -Raw -Encoding UTF8
$saveModuleMetadataTest = Get-Content (Join-Path $stageRoot 'Test-AgentSaveMetadata.ps1') -Raw -Encoding UTF8
if ($agentCliSource -notmatch 'Get-AgentSaveModuleIds -SavePath \$savePath' -or $saveModuleMetadataSource -notmatch 'Save metadata header length is invalid' -or $saveModuleMetadataTest -notmatch 'TruncatedHeaderRejected') { throw 'Save load must honor a validated, fixture-specific module set instead of guessing a default.' }
$startupEvidenceScript = Join-Path $stageRoot 'HarnessStartupEvidence.ps1'
$contextFocusScript = Join-Path $stageRoot 'Set-ContextFocus.ps1'
$researchReadinessScript = Join-Path $stageRoot 'HarnessResearchReadiness.ps1'
$researchReadinessSource = Get-Content $researchReadinessScript -Raw -Encoding UTF8
. $researchReadinessScript
$contextFocusSource = Get-Content $contextFocusScript -Raw -Encoding UTF8
. $researchReadinessScript
$projectFile = Get-Content (Join-Path $modRoot 'ChronicleFramework.csproj') -Raw -Encoding UTF8
$developmentDoc = Get-Content (Join-Path $docsRoot 'DEVELOPMENT.md') -Raw -Encoding UTF8
if ($developmentDoc -notmatch '不使用 Windows Computer Use 向游戏窗口发送鼠标或键盘输入' -or $developmentDoc -notmatch '会自动激活目标窗口' -or $developmentDoc -notmatch '后台窗口输入不会激活窗口') { throw 'Game UI automation must remain disabled until non-activating isolated input is evidenced.' }
$designDoc = Get-Content (Join-Path $docsRoot 'DESIGN.md') -Raw -Encoding UTF8
$inventoryDoc = Get-Content (Join-Path $docsRoot 'SYSTEM_INVENTORY.md') -Raw -Encoding UTF8
$rootAgents = Get-Content (Join-Path $projectRoot 'AGENTS.md') -Raw -Encoding UTF8
$runtimeGameRoot = if ($localSettings -and $localSettings.gameRoot) { [IO.Path]::GetFullPath([string]$localSettings.gameRoot) } else { $null }
$gitIgnore = Get-Content (Join-Path $projectRoot '.gitignore') -Raw -Encoding UTF8
$sourceManifestPath = Join-Path $modulePackageRoot 'SubModule.xml'
$moduleStringsSourcePath = Join-Path $modulePackageRoot 'ModuleData\global_strings.xml'
$moduleStringsSource = Get-Content $moduleStringsSourcePath -Raw -Encoding UTF8
$moduleManifestSource = Get-Content $sourceManifestPath -Raw -Encoding UTF8
$mainlinePath = Join-Path $docsRoot ([string]$contextState.current.path)
$mainlineDoc = Get-Content $mainlinePath -Raw -Encoding UTF8
if (-not (Test-Path (Join-Path $docsRoot 'ContextState.json'))) { throw 'ContextState.json is missing.' }
if ($runtimeGameRoot) {
    $runtimeAgentsPath = Join-Path $runtimeGameRoot 'AGENTS.md'
    if (Test-Path -LiteralPath $runtimeAgentsPath) {
        $trackedAgentsHash = (Get-FileHash -LiteralPath (Join-Path $projectRoot 'AGENTS.md') -Algorithm SHA256).Hash
        $runtimeAgentsHash = (Get-FileHash -LiteralPath $runtimeAgentsPath -Algorithm SHA256).Hash
        if ($trackedAgentsHash -ne $runtimeAgentsHash) { throw 'Repository AGENTS.md and game-workspace AGENTS.md copies have diverged.' }
    }
}
if ($projectFile -match 'TestResults') { throw 'ChronicleFramework.csproj must not reference generated evidence under TestResults; the Mod project owns its own directory and evidence lives beside it, not inside it.' }

if ($harnessScript -notmatch "HarnessContractVersion\s*=\s*'$contractVersion'") {
    throw "Run-Harness.ps1 does not declare contract version $contractVersion."
}
if ($harnessScript -notmatch 'function Get-HarnessConfiguredProviderCredential' -or
    $harnessScript -notmatch 'Get-ChronicleProviderCredential -Endpoint \$endpoint' -or
    $harnessScript -notmatch 'providerKeyVariable = \[string\]\$providerCredential\.EnvironmentVariableName' -or
    $harnessScript -notmatch 'SetEnvironmentVariable\(\$providerKeyVariable, \[string\]\$providerCredential\.Value' -or
    $harnessScript -notmatch 'SetEnvironmentVariable\(\$providerKeyVariable, \$savedProviderKey' -or
    $harnessScript -notmatch 'savedProviderKey') {
    throw 'Real-model Campaign phases must inject only the credential selected for their configured endpoint and restore the caller process environment afterward.'
}
if ($harnessScript -notmatch "PersistentEycMaxProviderDecisionsPerContinuation\s*=\s*1" -or
    $persistentStoryModeCampaignScript -notmatch "MaxProviderDecisionsPerContinuation\s*=\s*1" -or
    $harnessScript -notmatch "PersistentEycMaxHttpRequestsPerDecision\s*=\s*1" -or
    $harnessScript -notmatch '-MaxHttpRequestsPerDecision \$PersistentEycMaxHttpRequestsPerDecision' -or
    $persistentStoryModeCampaignScript -notmatch '\[ValidateRange\(1,2\)\]\[int\]\$MaxHttpRequestsPerDecision = 1' -or
    $persistentStoryModeCampaignScript -notmatch "'-MaxHttpRequestsPerDecision',\[string\]\`$MaxHttpRequestsPerDecision" -or
    $agentLiveModelLoopSource -notmatch '\[ValidateRange\(1,2\)\]\[int\]\$MaxHttpRequestsPerDecision = 1' -or
    $agentLiveModelLoopSource -notmatch "CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION = \[string\]\`$MaxHttpRequestsPerDecision" -or
    $harnessScript -notmatch "FreshStoryModeModel\s*=\s*''" -or
    $harnessScript -notmatch 'Select an explicit model ID with -FreshStoryModeModel' -or
    $harnessScript -match '\[ValidateSet\([^\r\n]*\)\]\[string\]\$FreshStoryModeModel' -or
    $harnessScript -notmatch '\$modelRows \| Where-Object \{ \[string\]\$_.id -ceq \$FreshStoryModeModel \}') {
    throw 'Persistent StoryMode runs must default to one provider decision, accept provider-neutral model IDs, and verify the selected ID in the configured provider catalog before game start.'
}
if ($harnessScript -notmatch "'FreshStoryModeModelEvaluation' \{ @\('Preflight', 'ConfiguredModelPreflight', 'Build', 'Smoke', 'AgentHostPackage', 'FreshStoryModeModelEvaluation'\) \}" -or
    $harnessScript -notmatch "'PersistentEycCampaign' \{ @\('Preflight', 'ConfiguredModelPreflight', 'Build', 'AgentHostPackage', 'PersistentEycCampaign'\) \}" -or
    $harnessScript -notmatch "Invoke-Stage -Name 'ConfiguredModelPreflight'" -or
    $harnessScript -notmatch "direct-remote-openai-compatible" -or
    $harnessScript -notmatch 'InferenceRequests = 0' -or
    $harnessScript -notmatch 'BannerlordStarted = \$false') {
    throw 'Live Campaign phases must reject unavailable configured model routes before Build or any game startup and record that preflight sends no inference request or client launch.'
}
$autonomyStages = [regex]::Match($harnessScript, "'AgentHostEstablishClanAutonomyEvaluation'\s*\{\s*@\(([^)]*)\)")
$autonomyStageList = if ($autonomyStages.Success) { $autonomyStages.Groups[1].Value } else { '' }
if (-not $autonomyStages.Success -or
    $autonomyStageList.IndexOf('AgentHostPackage', [StringComparison]::Ordinal) -lt 0 -or
    $autonomyStageList.IndexOf('Smoke', [StringComparison]::Ordinal) -lt 0 -or
    $autonomyStageList.IndexOf('AgentHostPackage', [StringComparison]::Ordinal) -gt $autonomyStageList.IndexOf('Smoke', [StringComparison]::Ordinal) -or
    $autonomyStageList.IndexOf('Smoke', [StringComparison]::Ordinal) -gt $autonomyStageList.IndexOf('AgentHostEstablishClanAutonomyEvaluation', [StringComparison]::Ordinal) -or
    $autonomyStageList.IndexOf('AgentHostProvider', [StringComparison]::Ordinal) -ge 0) {
    throw 'Live StoryMode autonomy evaluation must run package/Native startup checks, then use the exact real-model EYC classification as its first model request; do not spend an extra model call in AgentHostProvider.'
}
if ($agentHostLiveModelLoopSource -notmatch 'Set-LiveModelProviderTimeout' -or
    $agentHostLiveModelLoopSource -notmatch 'Resolve-LiveModelProviderTimeout' -or
    $agentHostLiveModelLoopSource -notmatch 'timeoutOverrideContract' -or
    $agentHostLiveModelLoopSource -match '\$env:CHRONICLE_LLM_TIMEOUT_SECONDS\s*=\s*''(180|360)''') {
    throw 'Live-model scenario defaults must honor a bounded explicit CHRONICLE_LLM_TIMEOUT_SECONDS override instead of resetting it.'
}
if ($agentLiveModelLoopSource -notmatch 'if\s*\(\[string\]::IsNullOrWhiteSpace\(\$priorModelMaxTokens\)\)\s*\{\s*\$env:CHRONICLE_LLM_MAX_TOKENS\s*=\s*''256''\s*\}\s*else\s*\{\s*\$env:CHRONICLE_LLM_MAX_TOKENS\s*=\s*\$priorModelMaxTokens\s*\}') {
    throw 'The EYC live-model loop must keep its 256-token default while honoring an explicit caller output-token limit.'
}
if ($freeLlmApiProfileSource -notmatch 'function Get-FreeLLMAPIProxyTrace' -or
    $freeLlmApiProfileSource -notmatch 'function Test-FreeLLMAPIProxyTraceContract' -or
    $freshCampaignTestSource -notmatch 'Get-FreeLLMAPIProxyTrace' -or
    $freshCampaignTestSource -notmatch 'FreeLLMAPIUpstreamTrace') {
    throw 'Live StoryMode receipts must correlate FreeLLMAPI provider failures with local proxy-attempt metadata.'
}
. (Join-Path $stageRoot 'Get-FreeLLMAPIProfile.ps1')
$freeLlmApiTraceTest = Test-FreeLLMAPIProxyTraceContract
if (-not $freeLlmApiTraceTest.Passed -or $freeLlmApiTraceTest.ModelCalls -ne 0 -or $freeLlmApiTraceTest.RawProviderTextLogged) {
    throw 'FreeLLMAPI request-log correlation must pass its synthetic no-model redaction contract.'
}
if ($harnessScript -notmatch 'GitCommit' -or $harnessScript -notmatch 'SourceControl' -or $harnessScript -notmatch 'status --porcelain' -or $harnessScript -match 'TaskBoard|CensusDomainDoneCount|gh project|gh api|githubProjectNumber') { throw 'Harness receipts must record Git provenance and remain independent of GitHub task tracking.' }
if ($projectFile -notmatch 'ChronicleGameRoot' -or $harnessScript -notmatch 'ChronicleGameRoot=\$gameRoot' -or -not (Test-Path -LiteralPath (Join-Path $stageRoot 'Initialize-ChronicleWorkspace.ps1'))) { throw 'Cloned repositories must accept a local game path and provide a repeatable workspace initializer.' }
if ($projectFile -match 'Remove="(TestResults|AgentHost|agenthost)/\*\*/\*"') {
    throw 'Each project owns its own directory; the Mod project must not exclude sibling trees that no longer share its root.'
}
if ($projectFile -notmatch 'Reference Include="SandBox\.View"' -or $projectFile -notmatch 'Modules\\SandBox\\bin\\Win64_Shipping_Client\\SandBox\.View\.dll' -or $projectFile -notmatch 'Reference Include="TaleWorlds\.Core\.ViewModelCollection"' -or $projectFile -notmatch 'TaleWorlds\.Core\.ViewModelCollection\.dll' -or $projectFile -notmatch 'Reference Include="TaleWorlds\.InputSystem"' -or $projectFile -notmatch 'TaleWorlds\.InputSystem\.dll') { throw 'Native map inventory/menu and RecruitmentVM lifecycle support must bind to the installed 1.4.8 View, ViewModel, and InputSystem assemblies.' }
