#Requires -Version 7.0

# Capture and battle: continuous capture HWND binding, contact sheets, battle fixture and solo probe.
# Sources asserted here: HarnessVideoCapture.ps1, Test-AgentBattleFixture.ps1, Test-AgentVisualCapture.ps1, Test-AgentBattleMissionFormationProbe.ps1, AgentBattleMissionAdapter.cs, AgentMissionInputPatch.cs

$videoCaptureSource = Get-Content (Join-Path $stageRoot 'HarnessVideoCapture.ps1') -Raw -Encoding UTF8
. (Join-Path $stageRoot 'HarnessVideoCapture.ps1')
$agentHostCaptureProjectionSelfTest = Test-ChronicleAgentHostCaptureProjection
if (-not $agentHostCaptureProjectionSelfTest.Passed) { throw 'AgentHost visual decision projection self-test failed.' }
$agentBattleFixtureSource = Get-Content (Join-Path $stageRoot 'Test-AgentBattleFixture.ps1') -Raw -Encoding UTF8
$agentVisualCaptureSource = Get-Content (Join-Path $stageRoot 'Test-AgentVisualCapture.ps1') -Raw -Encoding UTF8
if ($videoCaptureSource -notmatch 'gfxcapture=hwnd=') { throw 'Continuous capture must bind only to an explicit Bannerlord HWND.' }
if ($videoCaptureSource -notmatch '\$contactStride\s*=\s*\[Math\]::Max\(1,\s*\[Math\]::Ceiling\(\$frames\s*/\s*\$contactFrameBudget\)\)' -or $videoCaptureSource -notmatch '\$contactSampleCount\s*=\s*\[Math\]::Max\(1,\s*\[Math\]::Ceiling\(\$frames\s*/\s*\[double\]\$contactStride\)\)' -or $videoCaptureSource -notmatch 'select=''not\(mod\(n\\,\$contactStride\)\)''.*scale=480:-2,format=yuvj420p,tile=\$contactTile') { throw 'Contact sheets must sample actual frame indices, stay within the frame budget, and use even JPEG-compatible dimensions.' }
if ($videoCaptureSource -notmatch 'FrameCoverageRatio' -or $videoCaptureSource -notmatch 'TimelineIndexPath' -or $videoCaptureSource -notmatch 'function Get-ChronicleContactFrameBudget' -or $videoCaptureSource -notmatch '\$durationBudget = \[Math\]::Ceiling\(\[Math\]::Max\(0, \$DurationSeconds\) / 5\.0\)' -or $videoCaptureSource -notmatch '\[Math\]::Min\(24, \[Math\]::Max\(\$durationBudget, \$transitionBudget\)\)' -or $videoCaptureSource -notmatch 'Remove-Item -LiteralPath \$Capture\.OutputPath' -or $videoCaptureSource -notmatch 'Explicit Bannerlord HWND' -or $videoCaptureSource -notmatch '\$contactColumns = \[Math\]::Min\(4, \$contactSampleCount\)' -or $videoCaptureSource -notmatch '\$contactRows = \[Math\]::Max\(1, \[Math\]::Ceiling' -or $videoCaptureSource -notmatch 'IsIconic\(\$handle\)' -or $videoCaptureSource -notmatch 'will not restore or move the user''s window') { throw 'Continuous capture must sample event transitions plus a bounded five-second overview cadence, reject minimized windows without moving them, and remove completed source clips after indexing.' }
if ($agentLiveModelLoopSource -match 'Stop-ChronicleWindowVideoCapture[^\r\n]*-KeepVideo' -or $agentLiveModelResumeSource -match 'Stop-ChronicleWindowVideoCapture[^\r\n]*-KeepVideo' -or $agentBattleFixtureSource -match 'Stop-ChronicleWindowVideoCapture[^\r\n]*-KeepVideo' -or $agentVisualCaptureSource -match 'Stop-ChronicleWindowVideoCapture[^\r\n]*-KeepVideo' -or $agentLiveModelLoopSource -notmatch 'SourceVideoRemovedAfterKeyframes') { throw 'No Harness path may retain a fully postprocessed MP4 merely because gameplay/model assertions failed; only postprocessing failures retain a clip.' }
if ($agentProtocolSource -notmatch 'MaxProtocolEventLogBytes = 16L \* 1024 \* 1024' -or $agentProtocolSource -notmatch 'AppendBoundedProtocolEventLog' -or -not $agentProtocolSource.Contains('currentBytes + incomingBytes > MaxProtocolEventLogBytes')) { throw 'The persistent Native protocol event log must enforce its 16 MiB bound.' }
if ($videoCaptureSource -notmatch "'mapSettlementTargets'.*'move'.*'recruitOptions'.*'recruit'.*'provision'.*'tradeConfirm'.*'rest'.*'providerDone'.*'modelLoopFailure'") { throw 'Contact-sheet/event timeline must preserve aligned map, trade, wait and failure transitions.' }
if ($videoCaptureSource -notmatch 'function Test-ChronicleFragmentedCaptureResilience' -or $videoCaptureSource -notmatch 'testsrc2=size=320x180:rate=5' -or $videoCaptureSource -notmatch 'Get-Command ffprobe\.exe' -or $videoCaptureSource -notmatch 'count_frames -select_streams v:0' -or $videoCaptureSource -notmatch 'TemporaryArtifactsRemoved' -or $agentLiveModelLoopSource -notmatch 'Test-ChronicleFragmentedCaptureResilience' -or $agentLiveModelLoopSource -notmatch 'CaptureRecoveryProof') { throw 'Live capture must prove that an abruptly interrupted fragmented MP4 remains decodable before starting a long Campaign run and retain a compact recovery receipt.' }
$battleFixtureSource = Get-Content (Join-Path $stageRoot 'Test-AgentBattleFixture.ps1') -Raw -Encoding UTF8
$battleMissionFormationProbeSource = Get-Content (Join-Path $stageRoot 'Test-AgentBattleMissionFormationProbe.ps1') -Raw -Encoding UTF8
$battleMissionAdapterSource = Get-Content (Join-Path $modRoot 'AgentBattleMissionAdapter.cs') -Raw -Encoding UTF8
$missionInputPatchSource = Get-Content (Join-Path $modRoot 'AgentMissionInputPatch.cs') -Raw -Encoding UTF8
if ($videoCaptureSource -notmatch 'keyframeInterval = \[Math\]::Max\(1, \$FrameRate \* 2\)' -or $videoCaptureSource -notmatch 'movflags \+frag_keyframe\+empty_moov\+default_base_moof' -or $videoCaptureSource -notmatch 'contactFrameBudget = Get-ChronicleContactFrameBudget' -or $videoCaptureSource -notmatch '\[Math\]::Ceiling\(\$frames / \$contactFrameBudget\)' -or $videoCaptureSource -notmatch '\$contactColumns = \[Math\]::Min\(4, \$contactSampleCount\)' -or $videoCaptureSource -notmatch 'frameExtractionFailures' -or $videoCaptureSource -notmatch 'agenthost-provider-response' -or $videoCaptureSource -notmatch 'camera-sample' -or $videoCaptureSource -notmatch '\$eventOnlyActions = @\(') { throw 'Continuous Bannerlord capture must preserve interrupted clips, include Host decisions and periodic camera samples, and remove completed source video after indexing.' }
if ($agentLiveModelLoopSource -notmatch 'Add-ChronicleAgentHostProgressCaptureEvents' -or $agentLiveModelLoopSource -notmatch 'AgentHostProgress\.jsonl' -or $videoCaptureSource -notmatch 'missionNavigateToAgent' -or $videoCaptureSource -notmatch 'PRIVATE_PROMPT_MARKER') { throw 'AgentHost video evidence must consume its sanitized decision log and cover repeated Native scene-navigation decisions without exposing prompts.' }
if ([regex]::Matches($agentLiveModelLoopSource, 'Add-ChronicleAgentHostProgressCaptureEvents').Count -lt 2 -or $agentLiveModelLoopSource -notmatch 'agentHostCaptureEventsWritten') { throw 'AgentHost decision timeline events must be merged in both successful and failed model-loop outcomes without duplicate appends.' }
if ($battleFixtureSource -notmatch 'BattleRewardTelemetry = if \(\$simulationFinish -and \$simulationFinish\.data\)') { throw 'PostBattle evidence must preserve the returned renown telemetry object.' }
if ($battleFixtureSource -notmatch "Invoke-AgentCli 'partyLootTransferOne'" -or $battleFixtureSource -notmatch 'PartyScreenLootSingleTransferVerified' -or $battleFixtureSource -notmatch 'loot-02b-single-transfer' -or $battleFixtureSource -notmatch 'PartyScreenDoneInquiryReceipt' -or $battleFixtureSource -notmatch 'remainingLootRows -ne 0' -or $battleFixtureSource -notmatch 'loot-02c-party-done-inquiry') { throw 'PostBattle must exercise the original Native single-row troop transfer, preserve its current-row receipt, and resolve a Done Inquiry only when no transferable Loot row remains.' }
if ($protocolSource -notmatch 'inventoryDone refuses to skip the Native' -or $protocolSource -notmatch 'GetElementCountOnSide\(TaleWorlds\.CampaignSystem\.Inventory\.InventoryLogic\.InventorySide\.OtherInventory\) > 0' -or $battleFixtureSource -notmatch 'prematureInventoryDoneRejected' -or $battleFixtureSource -notmatch 'prematureInventoryDonePreservedLoot' -or $battleFixtureSource -notmatch 'CampaignDayAtBattleSimulationStart' -or $battleFixtureSource -notmatch 'TimeControlModeAtPostBattleMapReturn') { throw 'Loot Done must not bypass the Native remaining-loot inquiry: guard unclaimed loot, test no-mutation refusal, then verify Take All/Done and record campaign clock around BattleSimulation.' }
if ($battleFixtureSource -notmatch 'Start-ChronicleWindowVideoCapture' -or $battleFixtureSource -notmatch 'BattleToLoot-events\.jsonl' -or $battleFixtureSource -notmatch 'videoCapturePassed') { throw 'PostBattle must collect continuous HWND video, aligned action/state events, and enforce capture coverage.' }
if ($battleFixtureSource -notmatch 'RenownProgressionPassed' -or $battleFixtureSource -notmatch 'ClanRenownDelta -gt 0' -or $battleFixtureSource -notmatch 'BattleRewardTelemetryPassed' -or $battleFixtureSource -notmatch 'playerContribution' -or $battleFixtureSource -notmatch 'winnerPartyAwards') { throw 'PostBattle must require both a positive renown delta and complete player reward telemetry for the P5 battle progression check.' }
if ($battleFixtureSource -notmatch 'EycQuestObservedAtStart' -or $battleFixtureSource -notmatch 'EycJournalRenownBeforeBattle' -or $battleFixtureSource -notmatch 'EycJournalRenownAfterBattle' -or $battleFixtureSource -notmatch 'Read-EycJournalRenown' -or $harnessScript -notmatch '-LoadSaveName \$BattleSimulationSourceSaveName -Scenario PostBattle -CaptureFrames') { throw 'PostBattle must optionally read the original EYC Journal on a selected disposable source fixture and retain its before/after Renown progress alongside Clan Renown telemetry.' }
if ($subModuleSource -notmatch 'preserveSoloMainParty \? 0 : Math\.Max\(0, 20 - mainParty\.MemberRoster\.TotalManCount\)' -or $subModuleSource -notmatch 'enemyCount = preserveSoloMainParty \? 11 : 19' -or $subModuleSource -notmatch 'fixtureOffset = preserveSoloMainParty \? 5\.0f : 0\.5f' -or $subModuleSource -notmatch 'enemyParty\.Ai\.DisableAi\(\)' -or $subModuleSource -notmatch 'opponentAiDisabledForBattleProbe' -or $subModuleSource -match 'RestartPlayerEncounter\(enemyParty\.Party' -or $battleFixtureSource -notmatch 'fixtureEnemyIsEncountered' -or $battleFixtureSource -notmatch 'Native pursuit lost the disposable looter target' -or $harnessScript -notmatch 'PostBattleChild\.log' -or $harnessScript -notmatch 'BattleFixtureChild\.log') { throw 'Battle fixtures must preserve a one-member MainParty versus eleven hostile looters at a non-overlapping map position, scale ordinary rosters separately, use Native pursuit/encounter, retain opponent AI for Retreat coverage, fail promptly on target loss, and retain child-process output.' }
if ($battleMissionFormationProbeSource -notmatch '\[switch\]\$SoloMainHero' -or $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'resume'" -or $battleMissionFormationProbeSource -notmatch 'id -eq ''chronicle_harness_looters'' -and \$_.hostile' -or $battleMissionFormationProbeSource -notmatch 'Capture-NativeFrame' -or $battleMissionFormationProbeSource -notmatch 'native-target-selected-but-waiting' -or $battleMissionFormationProbeSource -notmatch 'nativeDeploymentPreconditionDiagnostic = \$hostMissionResult\.nativeDeploymentPreconditionDiagnostic' -or $battleMissionFormationProbeSource -notmatch 'nativeDeploymentCompletedByNative' -or $battleMissionFormationProbeSource -notmatch 'formationCount -gt 0' -or $battleMissionFormationProbeSource -notmatch 'nativeBattleStatusAfterHost' -or $battleMissionFormationProbeSource -notmatch 'HostNativeBattlePreconditionFailure\.bmp' -or $agentHostBattleMissionLoopSource -notmatch 'battle-mission-native-spontaneous-deployment-transition-unverified' -or $agentHostBattleMissionLoopSource -notmatch 'availablePlayerFormationCount > 0' -or $harnessScript -notmatch '\[switch\]\$BattleMissionSoloMainHeroProbe' -or $agentHostProgramSource -notmatch 'solo-battle-fixture') { throw 'The opt-in solo MainHero battle probe must assert a one-member Native MainParty, target its isolated hostile fixture, preserve the exact Host precondition diagnostic/post-failure Mission status, skip empty F6, and verify Native deployment reconciliation.' }
if ($battleMissionFormationProbeSource -notmatch '\[switch\]\$SoloMainHero' -or $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'resume'" -or $battleMissionFormationProbeSource -notmatch 'id -eq ''chronicle_harness_looters'' -and \$_.hostile' -or $battleMissionFormationProbeSource -notmatch 'Capture-NativeFrame' -or $battleMissionFormationProbeSource -notmatch 'native-target-selected-but-waiting' -or $battleMissionFormationProbeSource -notmatch 'nativeDeploymentPreconditionDiagnostic = \$hostMissionResult\.nativeDeploymentPreconditionDiagnostic' -or $battleMissionFormationProbeSource -notmatch 'nativeDeploymentCompletedByNative' -or $battleMissionFormationProbeSource -notmatch 'formationCount -gt 0' -or $battleMissionFormationProbeSource -notmatch 'nativeBattleStatusAfterHost' -or $battleMissionFormationProbeSource -notmatch 'HostNativeBattlePreconditionFailure\.bmp' -or $agentHostBattleMissionLoopSource -notmatch 'battle-mission-native-spontaneous-deployment-transition-unverified' -or $agentHostBattleMissionLoopSource -notmatch 'availablePlayerFormationCount > 0' -or $harnessScript -notmatch '\[switch\]\$BattleMissionSoloMainHeroProbe' -or $agentHostProgramSource -notmatch 'solo-battle-fixture' -or $subModuleSource -notmatch 'preserveSoloMainParty \? 11 : 19') { throw 'The opt-in solo MainHero battle probe must reproduce the EYC 1-vs-11 looter boundary, preserve the exact Host precondition diagnostic/post-failure Mission status, skip empty F6, and verify Native deployment reconciliation.' }
if ($battleFixtureSource -notmatch 'inventoryLootItemCountAfter -ne 0' -or $battleFixtureSource -match 'inventoryItemsTransferred -lt \$inventoryLootItemCountBefore|inventoryItemsTransferred -gt 0') { throw 'PostBattle must verify Native Loot All by checking zero remaining loot; inventory slot-count growth is not a valid item-transfer count when existing stacks merge.' }
if ($battleMissionFormationProbeSource -notmatch 'CHRONICLE_HARNESS_AGENT_INPUT_LOCK = ''1''' -or
    $battleMissionFormationProbeSource.IndexOf('$env:CHRONICLE_HARNESS_AGENT_INPUT_LOCK = ''1''', [StringComparison]::Ordinal) -gt $battleMissionFormationProbeSource.IndexOf("Invoke-AgentCli 'load'", [StringComparison]::Ordinal) -or
    $battleMissionFormationProbeSource -notmatch 'desktopInputIsolationPassed' -or
    $battleMissionFormationProbeSource -notmatch 'CursorUnrestrictedAcrossDesktop' -or
    $battleMissionFormationProbeSource -notmatch 'harnessInputOwnershipConfirmed' -or
    $battleMissionFormationProbeSource -notmatch 'agent-mission-input-blocked' -or
    $battleMissionFormationProbeSource -notmatch 'mission safety gate failed') {
    throw 'Native battle Mission probes must arm and verify non-foreground windowing plus empty Mission input before performing any in-Mission action.'
}
if ($harnessScript -notmatch "'BattleMissionInputIsolationProbe'" -or
    $harnessScript -notmatch "'BattleMissionInputIsolationProbe' \{ @\('Preflight', 'Build', 'BattleMissionInputIsolationProbe'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'BattleMissionInputIsolationProbe'" -or
    $battleMissionFormationProbeSource -notmatch '\[switch\]\$ProbeDesktopInputIsolationOnly' -or
    $battleMissionFormationProbeSource -notmatch 'BattleMissionDesktopInputIsolation\.json' -or
    $battleMissionFormationProbeSource -notmatch '3D Mission desktop input isolation probe failed' -or
    $battleMissionFormationProbeSource -notmatch 'scenario = ''native-battle-mission-desktop-input-isolation-no-model''') {
    throw 'The desktop-input isolation phase must stop at the first safe 3D Mission state, record OS cursor/focus and Native input-lock evidence, use no model, and clean its disposable fixture.'
}
if ($harnessScript -notmatch "'BattleMissionFormationProbe'" -or $harnessScript -notmatch '\$battleMissionFormationProbeScript' -or
    $harnessScript -notmatch "'BattleMissionFormationProbe' \{ @\('Preflight', 'Build', 'BattleMissionFormationProbe'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'BattleMissionFormationProbe'" -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'missionDelegateTroops'" -or
    $battleMissionFormationProbeSource -notmatch 'isDetachedFromFormation' -or
    $battleMissionFormationProbeSource -notmatch 'sourceSaveHashBefore' -or
    $battleMissionFormationProbeSource -notmatch 'modelCalls = 0') {
    throw 'The opt-in Battle Mission formation probe must use the Native CLI, collect MainAgent formation/ownership/health, keep model calls at zero, preserve its source save and remain outside All.'
}
if ($harnessScript -notmatch "'BattleMissionControllerProbe'" -or
    $harnessScript -notmatch "'BattleMissionControllerProbe' \{ @\('Preflight', 'Build', 'BattleMissionControllerProbe'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'BattleMissionControllerProbe'" -or
    $battleMissionFormationProbeSource -notmatch 'ProbeMainAgentAiController' -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'harnessMainAgentAiControllerProbe'" -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'harnessMainAgentAiSurrogateControllerProbe'" -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'harnessRefreshMainAgentFormationAiProbe'" -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'harnessNotifyMainAgentAiMovementOrderProbe'" -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'harnessRestoreMainAgentAiControllerProbe'" -or
    $battleMissionFormationProbeSource -notmatch 'formation\.hasActiveAiBehavior' -or
    $battleMissionAdapterSource -notmatch 'hasActiveAiBehavior' -or
    $battleMissionAdapterSource -notmatch 'activeAiBehaviorType' -or
    $battleMissionAdapterSource -notmatch 'activeAiOrderType' -or
    $battleMissionAdapterSource -notmatch 'distanceToActiveAiOrderTarget' -or
    $battleMissionAdapterSource -notmatch 'GetMethod\("SetWatchState"' -or
    $battleMissionAdapterSource -notmatch 'IsPlayerTroopInFormation' -or
    $battleMissionAdapterSource -notmatch 'OnUnitJoinOrLeave\(formation, hero, isJoining: true\)' -or
    $protocolSource -notmatch 'UpdateMainAgentAiControllerProbeLease\(\)' -or
    $protocolSource -notmatch 'ClearMainAgentAiControllerProbeLease\("protocol-stopped"\)' -or
    $agentCliSource -notmatch 'harnessMainAgentAiSurrogateControllerProbe' -or
    $agentHostDecisionCycleSource -match 'harnessMainAgentAiSurrogateControllerProbe' -or
    $agentCliSource -notmatch 'harnessRefreshMainAgentFormationAiProbe' -or
    $agentHostDecisionCycleSource -match 'harnessRefreshMainAgentFormationAiProbe' -or
    $agentCliSource -notmatch 'harnessNotifyMainAgentAiMovementOrderProbe' -or
    $agentHostDecisionCycleSource -match 'harnessNotifyMainAgentAiMovementOrderProbe' -or
    $harnessScript -notmatch "'BattleMissionRtsCameraProbe' \{ @\('Preflight', 'Build', 'BattleMissionRtsCameraProbe'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'BattleMissionRtsCameraProbe'" -or
    $battleMissionFormationProbeSource -notmatch 'ProbeMainAgentRtsCameraBehavior' -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'harnessMainAgentAiRtsCameraProbe'" -or
    $agentCliSource -notmatch 'harnessMainAgentAiRtsCameraProbe' -or
    $agentHostDecisionCycleSource -match 'harnessMainAgentAiRtsCameraProbe' -or
    $harnessScript -notmatch "'BattleMissionMovementInputProbe' \{ @\('Preflight', 'Build', 'BattleMissionMovementInputProbe'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'BattleMissionMovementInputProbe'" -or
    $battleMissionFormationProbeSource -notmatch 'ProbeBattleMovementInput' -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'harnessBattleMovementInputProbe'" -or
    $agentCliSource -notmatch 'harnessBattleMovementInputProbe' -or
    $agentHostDecisionCycleSource -match 'harnessBattleMovementInputProbe' -or
    $harnessScript -notmatch "'BattleMissionAgentNavigatorProbe' \{ @\('Preflight', 'Build', 'BattleMissionAgentNavigatorProbe'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'BattleMissionAgentNavigatorProbe'" -or
    $battleMissionFormationProbeSource -notmatch 'ProbeBattleAgentNavigator' -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'harnessBattleAgentNavigatorProbe'" -or
    $agentCliSource -notmatch 'harnessBattleAgentNavigatorProbe' -or
    $agentHostDecisionCycleSource -match 'harnessBattleAgentNavigatorProbe' -or
    $protocolSource -notmatch 'harnessBattleAgentNavigatorProbe requires the active stopped Campaign field Battle Mission' -or
    $protocolSource -notmatch 'isActiveBattleNavigatorProbe = _missionNavigationBattleProbe' -or
    $protocolSource -notmatch 'battleProbeFormation\.SetControlledByAI\(battleProbeFormationAiOriginal\.Value\)' -or
    $protocolSource -notmatch 'BeginBattleMovementProbe\(movementProbeMission, movementProbeMainAgent\)' -or
    $protocolSource -notmatch 'missionInput requires a supported non-battle town or Tavern Location Mission' -or
    $harnessScript -notmatch "'BattleMissionMovementInputProbe' \{ @\('Preflight', 'Build', 'BattleMissionMovementInputProbe'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'BattleMissionMovementInputProbe'" -or
    $battleMissionFormationProbeSource -notmatch 'ProbeBattleMovementInput' -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'harnessBattleMovementInputProbe'" -or
    $protocolSource -notmatch 'harnessBattleMovementInputProbe requires the active stopped Campaign field Battle Mission' -or
    $protocolSource -notmatch 'missionInput requires a supported non-battle town or Tavern Location Mission' -or
    $missionInputPatchSource -notmatch 'IsActiveBattleMovementProbe' -or
    $protocolSource -notmatch '_missionNavigationBattleProbe && mission != null' -or
    $protocolSource -notmatch '_missionNavigationOwner\?\.Controller == AgentControllerType\.AI' -or
    $agentHostDecisionCycleSource -match 'harnessBattleMovementInputProbe' -or
    $agentHostDecisionCycleSource -match 'harnessMainAgentAiControllerProbe') {
    throw 'The opt-in MainAgent AI-controller probe must remain bounded and restorable in Native Harness code, perform no model work, and stay out of the production AgentHost action catalog.'
}
if ($harnessScript -notmatch "'BattleMissionNativeAiHandoffProbe' \{ @\('Preflight', 'Build', 'BattleMissionNativeAiHandoffProbe'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'BattleMissionNativeAiHandoffProbe'" -or
    $battleMissionFormationProbeSource -notmatch 'ProbeMainAgentNativeAiHandoff' -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'harnessMainAgentNativeAiHandoffProbe'" -or
    $agentCliSource -notmatch 'harnessMainAgentNativeAiHandoffProbe' -or
    $agentHostDecisionCycleSource -match 'harnessMainAgentNativeAiHandoffProbe' -or
    $protocolSource -notmatch 'harnessMainAgentNativeAiHandoffProbe' -or
    $battleMissionAdapterSource -notmatch 'ApplyNativeMainAgentAiHandoff\(mainAgent, mission\)' -or
    $battleMissionAdapterSource -notmatch 'CommonAIComponent' -or
    $battleMissionAdapterSource -notmatch 'HumanAIComponent' -or
    $battleMissionAdapterSource -notmatch 'DisableScriptedMovement\(\)' -or
    $battleMissionAdapterSource -notmatch 'ResetNativeThirdPersonBattleCamera' -or
    $battleMissionAdapterSource -notmatch 'NativeThirdPersonBattleCameraElevation = 0f' -or
    $battleMissionAdapterSource -notmatch 'NativeThirdPersonBattleCameraNearVerticalThreshold = -0\.7f' -or
    $battleMissionAdapterSource -notmatch 'EnforceNativeAiBattleCamera' -or
    $missionInputPatchSource -notmatch 'IsBattleCameraPatchInstalled' -or
    $missionInputPatchSource -notmatch 'MissionScreen.UpdateCamera' -or
    $battleMissionFormationProbeSource -notmatch 'nativeBattleCameraCorrectionPatchInstalled' -or
    $battleMissionFormationProbeSource -notmatch 'missionAutoDeploy' -or
    $battleMissionFormationProbeSource -notmatch 'nativeAiHandoffCameraFrame' -or
    $battleMissionFormationProbeSource -notmatch 'nativeAiHandoffSustainedCameraFrame' -or
    $battleMissionFormationProbeSource -notmatch 'nativeAiHandoffExpectedCameraElevation' -or
    $battleMissionFormationProbeSource -notmatch 'activeAiCameraSamples' -or
    $battleMissionFormationProbeSource -notmatch 'invalidCameraSamples' -or
    $battleMissionFormationProbeSource -notmatch 'cameraInitialFacingErrorRadians' -or
    $battleMissionFormationProbeSource -notmatch 'cameraFacingYawErrorMaxRadians' -or
    $battleMissionFormationProbeSource -notmatch 'cameraVerticalOffsetRangeMeters' -or
    $battleMissionFormationProbeSource -notmatch 'cameraMotionComparison' -or
    $battleMissionFormationProbeSource -notmatch 'playerControlledMainHeroOrderViewClose' -or
    $battleMissionFormationProbeSource -notmatch 'cameraBaselinePreparation' -or
    $battleMissionFormationProbeSource -notmatch 'playerControlledMainHeroCameraMotionSamples' -or
    $battleMissionFormationProbeSource -notmatch 'nativeAiCameraMotionSamples' -or
    $battleMissionFormationProbeSource -notmatch 'playerControlledMainHeroNormalViewSampleCount' -or
    $battleMissionFormationProbeSource -notmatch 'comparisonValid' -or
    $battleMissionFormationProbeSource -notmatch 'Get-CameraMotionSummary' -or
    $battleMissionFormationProbeSource -notmatch 'nativeHandoffRestoredState.data.camera' -or
    $battleMissionFormationProbeSource -notmatch 'Start-ChronicleWindowVideoCapture' -or
    $battleMissionFormationProbeSource -notmatch 'Stop-ChronicleWindowVideoCapture' -or
    $battleMissionFormationProbeSource -notmatch 'periodicFrameSamples' -or
    $battleMissionAdapterSource -notmatch 'LookDirectionAsAngle' -or
    $battleMissionAdapterSource -notmatch 'Native keeps a player camera bearing fixed' -or
    $battleMissionAdapterSource -notmatch 'Track the agent heading after the' -or
    $battleMissionAdapterSource -notmatch 'NativeThirdPersonBattleCameraBearingFollowThreshold = 0\.02f' -or
    $battleMissionAdapterSource -notmatch 'RestoreNativeThirdPersonBattleCamera' -or
    $battleMissionAdapterSource -notmatch '_mainAgentAiProbeOriginalCameraBearing' -or
    $battleMissionAdapterSource -notmatch 'RestoreNativeMainAgentAiHandoff') {
    throw "The Native MainHero AI lease must initialize a readable view, track MainHero heading after the Native camera update, correct only the overhead clamp, and restore the user's original view; zero-model tests must retain camera-motion evidence."
}
if ($agentCliSource -notmatch "'harnessCloseMissionOrderMenu'" -or
    $agentCliSource -notmatch "'harnessPrepareCameraMotionBaseline'" -or
    $agentProtocolSource -notmatch 'case "harnessCloseMissionOrderMenu"' -or
    $agentProtocolSource -notmatch 'case "harnessPrepareCameraMotionBaseline"' -or
    $battleMissionAdapterSource -notmatch 'CloseNativeMissionOrderViewFromHarness' -or
    $battleMissionAdapterSource -notmatch 'GetMethod\("OnEscape"' -or
    $battleMissionAdapterSource -notmatch 'PrepareNativeThirdPersonCameraMotionBaseline' -or
    $agentProtocolSource -notmatch 'harnessCloseMissionOrderMenu is restricted to a disposable battle-fixture Harness run' -or
    $agentProtocolSource -notmatch 'harnessPrepareCameraMotionBaseline is restricted to a disposable battle-fixture Harness run') {
    throw 'Camera-motion comparison setup must use the Native MissionScreen Escape path and a disposable-fixture-only third-person camera baseline.'
}
if ($protocolSource -notmatch 'case "missionAutopilotMainAgent"' -or
    $protocolSource -notmatch 'case "missionAutoDeploy"' -or
    $battleMissionAdapterSource -notmatch 'BeginMainAgentNativeAiAutopilotLease' -or
    $battleMissionAdapterSource -notmatch 'AutoDeployCurrentBattleDeployment' -or
    $battleMissionAdapterSource -notmatch 'MissionOrderDeploymentControllerVM.ExecuteDeployPlayerSide' -or
    $agentCliSource -notmatch "'missionAutopilotMainAgent'" -or
    $agentCliSource -notmatch "'missionAutoDeploy'" -or
    $agentHostMailboxSource -notmatch 'missionAutopilotMainAgent' -or
    $agentHostMailboxSource -notmatch 'missionAutoDeploy' -or
    $agentHostBattleMissionLoopSource -notmatch 'AutopilotMainAgentBattleMissionAsync' -or
    $agentHostBattleMissionLoopSource -notmatch 'AutoDeployBattleMissionAsync' -or
    $agentHostBattleMissionLoopSource -notmatch 'nativeReadyCallbackDispatchedByBridge' -or
    $agentHostBattleMissionLoopSource -notmatch 'agenthost-native-battle-autopilot' -or
    $agentHostBattleMissionLoopSource -notmatch 'mainHeroNativeAiControlMaintained' -or
    $agentHostDecisionCycleSource -match 'missionAutopilotMainAgent|missionAutoDeploy') {
    throw 'Native battle setup and MainHero AI handoff must remain Host-only, reuse verified original deployment callbacks, and be excluded from model action catalogs.'
}
if ($harnessScript -notmatch "'BattleMissionHostNativeAiAutopilotProbe' \{ @\('Preflight', 'Build', 'AgentHostPackage', 'BattleMissionHostNativeAiAutopilotProbe'\) \}" -or
    $harnessScript -match "'All' \{[^\r\n]*'BattleMissionHostNativeAiAutopilotProbe'" -or
    $harnessScript -notmatch 'retainPackageForSameSessionRuntime\s*=\s*\$Phase\s*-in\s*@\([^\r\n]*BattleMissionHostNativeAiAutopilotProbe' -or
    $battleMissionFormationProbeSource -notmatch 'ProbeAgentHostNativeAiAutopilot' -or
    $battleMissionFormationProbeSource -notmatch '--native-battle-mission-loop-harness' -or
    $agentHostProgramSource -notmatch '--native-battle-mission-loop-harness' -or
    $agentHostProgramSource -notmatch '(?s)CHRONICLE_HARNESS_MODE.*battle-fixture' -or
    $harnessScript -notmatch '\[switch\]\$BattleMissionSoloMainHeroProbe' -or
    $battleMissionFormationProbeSource -notmatch '\[switch\]\$SoloMainHero' -or
    $battleMissionFormationProbeSource -notmatch "Invoke-AgentCli 'resume'" -or
    $subModuleSource -notmatch 'preserveSoloMainParty' -or
    $agentHostProgramSource -notmatch 'solo-battle-fixture' -or
    $agentHostBattleMissionLoopSource -notmatch 'AutopilotMainAgentBattleMissionAsync' -or
    $agentHostBattleMissionLoopSource -notmatch 'nativeDeploymentAutoDeployIssued' -or
    $agentHostBattleMissionLoopSource -notmatch 'NativeDeploymentCompletedByNative' -or
    $agentHostBattleMissionLoopSource -notmatch 'battle-mission-loop-self-test-native-deployment-transition-not-reconciled' -or
    $agentHostBattleMissionLoopSource -notmatch 'battle-mission-native-spontaneous-deployment-transition-unverified' -or
    $agentHostBattleMissionLoopSource -notmatch 'battle-mission-native-deployment-command-rejected' -or
    $agentHostBattleMissionLoopSource -notmatch 'missionMainAgentControllerActive' -or
    $agentHostBattleMissionLoopSource -notmatch 'battle-mission-native-mainhero-autopilot-rejected' -or
    $battleMissionAdapterSource -notmatch 'double\.IsNaN\(value\) \|\| double\.IsInfinity\(value\)' -or
    $agentHostProgramSource -notmatch 'nativeReadyHandlerExceptionType' -or
    $battleMissionFormationProbeSource -notmatch 'deploymentStatusBeforeHost' -or
    $agentHostDecisionCycleSource -match 'missionAutopilotMainAgent|missionAutoDeploy') {
    throw 'The production Native battle loop integration probe must use a packaged Host and disposable battle, recover only from state-verified Native callbacks, record UI setup evidence, and keep internal battle actions out of model catalogs.'
}
if ($agentHostBattleMissionLoopSource -notmatch 'ReadBoolean\(deploymentUi, "viewInitialized"\)' -or
    $agentHostBattleMissionLoopSource -notmatch 'ReadBoolean\(deploymentUi, "readyCallbackBound"\)' -or
    $agentHostBattleMissionLoopSource -match 'if \(deploymentAutoDeployIssued && ReadBoolean\(deploymentUi, "viewAvailable"\)' -or
    $agentHostBattleSimulationLoopSource -notmatch '_deploymentReadyCallbackStatusReads >= 2' -or
    $agentHostBattleSimulationLoopSource -notmatch 'readyCallbackBoundAfter\\":false') {
    throw 'The Host must wait for the original Native Ready callback to be observed after Auto Deploy; a button being enabled alone is not a ready callback.'
}
if ($agentHostBattleMissionLoopSource -notmatch 'nonMainHeroAgentCount == 0' -or
    $battleMissionAdapterSource -notmatch 'nonMainHeroAgentCount' -or
    $battleMissionAdapterSource -notmatch 'agent\.IsHuman && agent\.Character != mainHeroCharacter' -or
    $agentHostBattleSimulationLoopSource -notmatch 'FakeDelegatedAttackBattleNativeClient\(soloMainHero: true\)' -or
    $agentHostBattleSimulationLoopSource -notmatch 'battle-loop-self-test-solo-mainhero-waits-for-native-deployment') {
    throw 'A lone MainHero must wait for the verified Native Deployment→Battle transition without invoking empty Auto Deploy/Ready/F6; the package test must cover that path separately from a troop-bearing side.'
}
