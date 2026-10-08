[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [switch]$TimeControlOnly
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$loop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Test-AgentLoopProvider.ps1'
$policy = Join-Path $PSScriptRoot 'Agent-DecisionLoopPolicy.ps1'
. $policy
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
if (-not (Test-Path $savePath)) { throw "Agent loop fixture not found: $savePath" }
$fixtureHashBefore = (Get-FileHash $savePath -Algorithm SHA256).Hash

function New-ObserveAgainPolicyFixture {
    param([string]$TimeMode = 'StoppablePlay', [bool]$Moving = $true, [bool]$EncounterActive = $false, [string]$MenuId = '', [string]$CurrentSettlementId = '')
    return [pscustomobject]@{
        status = 'completed'
        state = [pscustomobject]@{
            context = [pscustomobject]@{ gameState = 'MapState'; timeControlMode = $TimeMode; encounterActive = $EncounterActive; menuId = $MenuId; escapeMenuOpen = $false; inquiryOpen = $false }
            party = [pscustomobject]@{ isMoving = $Moving }
            location = [pscustomobject]@{ currentSettlementId = $CurrentSettlementId; targetSettlementId = 'village_test' }
        }
    }
}
$policyReceipt = [pscustomobject]@{ action = 'move'; status = 'completed'; state = [pscustomobject]@{ location = [pscustomobject]@{ targetSettlementId = 'village_test' } } }
$activeTravelPolicy = Get-ObserveAgainPolicy -Observation (New-ObserveAgainPolicyFixture) -PreviousActionReceipt $policyReceipt
$pausedTravelPolicy = Get-ObserveAgainPolicy -Observation (New-ObserveAgainPolicyFixture -TimeMode 'Stop') -PreviousActionReceipt $policyReceipt
$encounterTravelPolicy = Get-ObserveAgainPolicy -Observation (New-ObserveAgainPolicyFixture -TimeMode 'Stop' -Moving $true -EncounterActive $true -MenuId 'encounter_meeting') -PreviousActionReceipt $policyReceipt
$arrivedTravelPolicy = Get-ObserveAgainPolicy -Observation (New-ObserveAgainPolicyFixture -TimeMode 'Stop' -Moving $false -MenuId 'town' -CurrentSettlementId 'village_test') -PreviousActionReceipt $policyReceipt
$invalidTravelPolicy = Get-ObserveAgainPolicy -Observation (New-ObserveAgainPolicyFixture) -PreviousActionReceipt ([pscustomobject]@{ action = 'recruit'; status = 'completed'; state = [pscustomobject]@{ location = [pscustomobject]@{ targetSettlementId = 'village_test' } } })
$observeAgainPolicyVerified = ($activeTravelPolicy.Allowed -and -not $pausedTravelPolicy.Allowed -and $pausedTravelPolicy.Recoverable -and -not $encounterTravelPolicy.Allowed -and $encounterTravelPolicy.Recoverable -and -not $arrivedTravelPolicy.Allowed -and $arrivedTravelPolicy.Recoverable -and -not $invalidTravelPolicy.Allowed -and -not $invalidTravelPolicy.Recoverable)
if (-not $observeAgainPolicyVerified) { throw 'observeAgain policy must permit naturally advancing travel only, recover when time is stopped or an encounter/menu is active, and hard-reject requests without a matching Native move receipt.' }

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @()) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $TimeoutSeconds -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $unicodeBaseline = Invoke-AgentCli 'state'
    $expectedHeroName = [string]$unicodeBaseline.state.identity.heroName
    if ([string]::IsNullOrWhiteSpace($expectedHeroName)) { throw 'Unicode Agent transport regression requires the live Native MainHero name.' }
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $priorExpectedHeroName = $env:CHRONICLE_TEST_EXPECTED_HERO_NAME
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'unicodeRoundTrip'
    $env:CHRONICLE_TEST_EXPECTED_HERO_NAME = $expectedHeroName
    try {
        $unicodeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-unicode-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $unicodeExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        if ($null -eq $priorExpectedHeroName) { Remove-Item Env:CHRONICLE_TEST_EXPECTED_HERO_NAME -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_EXPECTED_HERO_NAME = $priorExpectedHeroName }
    }
    if ($unicodeExitCode -ne 0) { throw "Agent loop corrupted the live Unicode hero name across its process boundary: $unicodeOutput" }
    $unicodeTrace = $unicodeOutput | ConvertFrom-Json
    $unicodeRoundTripVerified = (@($unicodeTrace.trace).Count -eq 1 -and $unicodeTrace.trace[0].decision.action -eq 'state' -and $unicodeTrace.trace[0].actionReceipt.status -eq 'completed')
    if (-not $unicodeRoundTripVerified) { throw 'Agent loop did not complete the Unicode round-trip regression action.' }
    if ($TimeControlOnly) {
        $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
        $env:CHRONICLE_TEST_PROVIDER_MODE = 'timeModes'
        try {
            $timeModesOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 3 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-time-modes-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
            $timeModesExitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
            else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        }
        if ($timeModesExitCode -ne 0) { throw "Agent decision loop did not route native time controls: $timeModesOutput" }
        $timeModesTrace = $timeModesOutput | ConvertFrom-Json
        $timeModeSteps = @($timeModesTrace.trace)
        $timeControlsRouted = (
            $timeModeSteps.Count -eq 3 -and
            $timeModeSteps[0].decision.action -eq 'resume' -and
            $timeModeSteps[0].actionReceipt.data.requestedMode -eq 'play' -and
            $timeModeSteps[0].actionReceipt.status -eq 'completed' -and
            $timeModeSteps[1].decision.action -eq 'fastForward' -and
            $timeModeSteps[1].actionReceipt.data.requestedMode -eq 'fastForward' -and
            $timeModeSteps[1].actionReceipt.data.rawModeAfter -in @('StoppableFastForward','UnstoppableFastForward') -and
            $timeModeSteps[1].actionReceipt.status -eq 'completed' -and
            $timeModeSteps[2].decision.action -eq 'pause' -and
            $timeModeSteps[2].actionReceipt.data.requestedMode -eq 'pause' -and
            $timeModeSteps[2].actionReceipt.status -eq 'completed' -and
            $timeModeSteps[2].actionReceipt.data.effectiveModeAfter -in @('Stop','FastForwardStop')
        )
        $playNaturallyAdvancedBeforeNextClockDecision = (
            $timeModeSteps.Count -eq 3 -and
            [double]$timeModeSteps[1].actionReceipt.data.campaignDayBefore -gt [double]$timeModeSteps[0].actionReceipt.data.campaignDayAfter -and
            -not [bool]$timeModeSteps[1].actionReceipt.data.isMainPartyWaitingBefore
        )
        $fastForwardNaturallyAdvancedAfterSelection = (
            $timeModeSteps.Count -eq 3 -and
            [double]$timeModeSteps[1].observationAfter.campaignDay -gt [double]$timeModeSteps[1].actionReceipt.data.campaignDayAfter -and
            $timeModeSteps[1].actionReceipt.data.effectiveModeAfter -in @('StoppableFastForward','UnstoppableFastForward') -and
            -not [bool]$timeModeSteps[1].actionReceipt.data.isMainPartyWaitingAfter
        )
        $pauseHeldCampaignDay = (
            $timeModeSteps.Count -eq 3 -and
            [double]$timeModeSteps[2].observationAfter.campaignDay -eq [double]$timeModeSteps[2].actionReceipt.data.campaignDayAfter
        )
        $timeModesStop = Invoke-AgentCli 'stop'
        $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
        $env:CHRONICLE_TEST_PROVIDER_MODE = 'waitingResume'
        try {
            $waitingStart = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
            $waitingResumeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-waiting-resume-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
            $waitingResumeExitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
            else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        }
        if ($waitingResumeExitCode -ne 0) { throw "Agent decision loop did not resume native time from Hold/waiting: $waitingResumeOutput" }
        $waitingResumeTrace = ($waitingResumeOutput | ConvertFrom-Json).trace
        $waitingResumeVerified = (
            @($waitingResumeTrace).Count -eq 2 -and
            $waitingResumeTrace[0].decision.action -eq 'hold' -and
            $waitingResumeTrace[0].actionReceipt.status -eq 'completed' -and
            $waitingResumeTrace[1].decision.action -eq 'resume' -and
            $waitingResumeTrace[1].actionReceipt.status -eq 'completed' -and
            $waitingResumeTrace[1].actionReceipt.data.effectiveModeAfter -eq 'UnstoppablePlay' -and
            [bool]$waitingResumeTrace[1].actionReceipt.data.isMainPartyWaitingBefore -and
            [double]$waitingResumeTrace[1].observationAfter.campaignDay -gt [double]$waitingResumeTrace[1].actionReceipt.data.campaignDayAfter -and
            [bool]$waitingResumeTrace[1].observationAfter.state.context.isWaiting
        )
        $waitingResumeStop = Invoke-AgentCli 'stop'
        $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
        $timeControlResult = [ordered]@{
            ProviderKind = 'deterministic-test-only'
            ProcessId = $start.session.processId
            DecisionCount = $timeModeSteps.Count
            NativeTimeControlActionsRouted = $timeControlsRouted
            PlayModeNaturallyAdvancedBeforeFastForwardSelection = $playNaturallyAdvancedBeforeNextClockDecision
            FastForwardNaturallyAdvanced = $fastForwardNaturallyAdvancedAfterSelection
            PauseHeldCampaignDay = $pauseHeldCampaignDay
            WaitingHoldThenResumeAdvancedNaturally = $waitingResumeVerified
            TimeControlTrace = $timeModesTrace.trace
            WaitingResumeTrace = $waitingResumeTrace
            FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
            ProcessStopped = ($timeModesStop.processStopped -and $waitingResumeStop.processStopped)
        }
        $timeControlResult.Passed = ($timeControlsRouted -and $playNaturallyAdvancedBeforeNextClockDecision -and $fastForwardNaturallyAdvancedAfterSelection -and $pauseHeldCampaignDay -and $waitingResumeVerified -and $timeControlResult.FixtureUnchanged -and $timeControlResult.ProcessStopped)
        $timeControlJson = $timeControlResult | ConvertTo-Json -Depth 12
        if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
            Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentTimeControlLoopResult.json') -Value $timeControlJson -Encoding UTF8
        }
        $timeControlJson
        if (-not $timeControlResult.Passed) { exit 1 }
        return
    }

    $contextGoal = 'Harness contract check: inspect the current visible settlement list and stop after receiving its Native receipt.'
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $priorExpectedGoal = $env:CHRONICLE_TEST_EXPECTED_GOAL
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'decisionContext'
    $env:CHRONICLE_TEST_EXPECTED_GOAL = $contextGoal
    try {
        $contextOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal $contextGoal -AllowedActionNames 'mapSettlementTargets,move' -MaxDecisions 3 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-context-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $contextExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        if ($null -eq $priorExpectedGoal) { Remove-Item Env:CHRONICLE_TEST_EXPECTED_GOAL -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_EXPECTED_GOAL = $priorExpectedGoal }
    }
    if ($contextExitCode -ne 0) { throw "Agent provider request lost its explicit goal or product action catalog: $contextOutput" }
    $contextTrace = $contextOutput | ConvertFrom-Json
    $goalAndCatalogForwarded = (@($contextTrace.trace).Count -eq 2 -and
        $contextTrace.trace[0].decision.action -eq 'mapSettlementTargets' -and
        $contextTrace.trace[0].decision.rationale -match 'Context contract accepted goal' -and $contextTrace.trace[0].decision.rationale -match 'only the two requested map actions' -and
        $contextTrace.trace[1].decision.done -and
        $contextTrace.trace[1].previousActionReceipt.action -eq 'mapSettlementTargets' -and
        $contextTrace.trace[1].decision.reason -match 'prior Native receipt')
    if (-not $goalAndCatalogForwarded) { throw "Goal/action-catalog request regression failed: $($contextTrace | ConvertTo-Json -Depth 8 -Compress)" }

    $priorInvalidDecision = $env:CHRONICLE_TEST_INVALID_DECISION
    $env:CHRONICLE_TEST_INVALID_DECISION = 'recruit'
    try {
        $scopedInvalidOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -AllowedActionNames 'mapSettlementTargets,move' -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-scoped-invalid-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $scopedInvalidExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorInvalidDecision) { Remove-Item Env:CHRONICLE_TEST_INVALID_DECISION -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_INVALID_DECISION = $priorInvalidDecision }
    }
    $scopedActionRejected = ($scopedInvalidExitCode -ne 0 -and $scopedInvalidOutput -match 'not in the Agent CLI allowlist')
    if (-not $scopedActionRejected) { throw "Scoped action catalog did not restrict execution (exit=$scopedInvalidExitCode): $scopedInvalidOutput" }

    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'dynamicAvailabilityRecovery'
    try {
        $recoveryOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Recover from unavailable volunteer recruitment by selecting a currently available map action.' -AllowedActionNames 'mapSettlementTargets,move,recruitOptions,recruit' -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-action-recovery-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $recoveryExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($recoveryExitCode -ne 0) { throw "Dynamic action availability did not recover after a safe pre-Native rejection: $recoveryOutput" }
    $recoveryTrace = $recoveryOutput | ConvertFrom-Json
    $dynamicActionRecoveryVerified = (
        @($recoveryTrace.trace).Count -eq 2 -and
        $recoveryTrace.trace[0].control.kind -eq 'decision-rejected-before-native' -and
        $recoveryTrace.trace[0].actionAttempted -eq $false -and
        $recoveryTrace.trace[0].actionReceipt.status -eq 'rejected-before-native' -and
        $recoveryTrace.trace[1].decision.action -eq 'mapSettlementTargets' -and
        $recoveryTrace.trace[1].actionReceipt.status -eq 'completed' -and
        $recoveryTrace.actionsExecuted -eq 1
    )
    if (-not $dynamicActionRecoveryVerified) { throw "Decision loop did not block the unavailable action before Native and recover using the current catalog: $($recoveryTrace | ConvertTo-Json -Depth 8 -Compress)" }

    $markerRoot = if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) { $env:CHRONICLE_HARNESS_TEMP } else { [IO.Path]::GetTempPath() }
    $staleOfferMarker = Join-Path $markerRoot ('stale-offer-recovery-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $priorStaleOfferMarker = $env:CHRONICLE_TEST_STALE_OFFER_MARKER
    $env:CHRONICLE_TEST_STALE_OFFER_MARKER = $staleOfferMarker
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'staleOfferRecovery'
    try {
        $staleOfferOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Reach a safe visible settlement, recover from a stale volunteer offer without Native mutation, refresh offers, and recruit one affordable volunteer within capacity.' -AllowedActionNames 'mapSettlementTargets,move,recruitOptions,recruit' -MaxDecisions 24 -MaxElapsedSeconds 600 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-stale-offer-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $staleOfferExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
        if ($null -eq $priorStaleOfferMarker) { Remove-Item Env:CHRONICLE_TEST_STALE_OFFER_MARKER -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_STALE_OFFER_MARKER = $priorStaleOfferMarker }
        Remove-Item -LiteralPath $staleOfferMarker -Force -ErrorAction SilentlyContinue
    }
    if ($staleOfferExitCode -ne 0) { throw "Stale Native offer did not fail closed and recover: $staleOfferOutput" }
    $staleOfferTrace = $staleOfferOutput | ConvertFrom-Json
    $staleRejection = @($staleOfferTrace.trace | Where-Object { $_.control.kind -eq 'decision-rejected-before-native' -and $_.decision.action -eq 'recruit' } | Select-Object -First 1)
    $recoveredRecruitment = @($staleOfferTrace.trace | Where-Object { $_.decision.action -eq 'recruit' -and $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
    $staleOfferBlockedWithoutMutation = $false
    if ($staleRejection.Count -eq 1 -and $staleRejection[0].observationAfter.state) {
        $rejectedBefore = $staleRejection[0].observationBefore
        $rejectedAfter = $staleRejection[0].observationAfter
        $staleOfferBlockedWithoutMutation = (
            $staleRejection[0].actionAttempted -eq $false -and
            [bool]$staleRejection[0].actionReceipt.noNativeActionSent -and
            [string]$rejectedBefore.state.location.currentSettlementId -ceq [string]$rejectedAfter.state.location.currentSettlementId -and
            [string]$rejectedBefore.state.context.menuId -ceq [string]$rejectedAfter.state.context.menuId -and
            [int]$rejectedBefore.state.party.members -eq [int]$rejectedAfter.state.party.members -and
            [int]$rejectedBefore.state.economy.gold -eq [int]$rejectedAfter.state.economy.gold
        )
    }
    $staleOfferRecoveryVerified = (
        $staleOfferBlockedWithoutMutation -and $recoveredRecruitment.Count -eq 1 -and
        @($staleOfferTrace.trace | Where-Object { $_.decision.action -eq 'recruitOptions' -and $_.actionExecuted }).Count -eq 2 -and
        @($staleOfferTrace.trace | Where-Object { $_.decision.action -eq 'move' -and $_.actionExecuted }).Count -eq 1 -and
        $staleOfferTrace.termination.completedByProvider
    )
    if (-not $staleOfferRecoveryVerified) { throw "Stale offer was not blocked without a world change and followed by fresh Native offers/recruitment: $($staleOfferTrace | ConvertTo-Json -Depth 10 -Compress)" }

    $resetBeforeResumeTest = Invoke-AgentCli 'stop'
    if ($resetBeforeResumeTest.status -ne 'completed' -or -not $resetBeforeResumeTest.processStopped) { throw 'Could not cleanly stop the stale-offer scenario before the isolated Native movement/clock recovery regression.' }
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    if ($start.status -ne 'completed' -or -not $start.session.processId) { throw 'Could not reload the disposable Campaign fixture for the isolated Native movement/clock recovery regression.' }
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'unlistedResumeRecovery'
    try {
        $resumeRecoveryOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -Goal 'Move to one currently visible safe Settlement. Native map movement advances time naturally; never issue resume/pause/fastForward. If the provider proposes an unavailable clock action, recover with a fresh observation and observeAgain.' -AllowedActionNames 'mapSettlementTargets,move' -MaxDecisions 12 -MaxElapsedSeconds 600 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-unlisted-resume-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $resumeRecoveryExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($resumeRecoveryExitCode -ne 0) { throw "Unlisted resume proposal did not recover into Native bounded observation: $resumeRecoveryOutput" }
    $resumeRecoveryTrace = $resumeRecoveryOutput | ConvertFrom-Json
    $resumeRejection = @($resumeRecoveryTrace.trace | Where-Object { $_.control.kind -eq 'decision-rejected-before-native' -and $_.decision.requestedAction -ceq 'resume' } | Select-Object -First 1)
    $resumeRecoveryObserve = @($resumeRecoveryTrace.trace | Where-Object { $_.control.kind -eq 'bounded-observe-again' })
    $resumeFeedbackConsumed = @($resumeRecoveryTrace.trace | Where-Object { $_.decisionFeedback.kind -eq 'action-unavailable' -and $_.decisionFeedback.requestedAction -ceq 'resume' })
    $staleObserveRejection = @($resumeRecoveryTrace.trace | Where-Object { $_.control.kind -eq 'control-rejected-before-native' -and $_.control.requestedControl -ceq 'observeAgain' } | Select-Object -First 1)
    $staleObserveFeedbackConsumed = @($resumeRecoveryTrace.trace | Where-Object { $_.decisionFeedback.kind -eq 'control-unavailable' -and $_.decisionFeedback.requestedControl -ceq 'observeAgain' })
    $staleObserveAgainRejectedWithoutNativeAction = (
        $staleObserveRejection.Count -eq 1 -and -not [bool]$staleObserveRejection[0].actionAttempted -and
        [bool]$staleObserveRejection[0].actionReceipt.noNativeActionSent -and $staleObserveFeedbackConsumed.Count -ge 1
    )
    $nativeTimeActions = @($resumeRecoveryTrace.trace | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -in @('resume','pause','fastForward') })
    $moveActions = @($resumeRecoveryTrace.trace | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -eq 'move' })
    $moveReceiptStep = @($resumeRecoveryTrace.trace | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -eq 'move' } | Select-Object -First 1)
    $finalResumeObservation = if ($resumeRecoveryTrace.trace.Count -gt 0 -and $resumeRecoveryTrace.trace[-1].observationAfter) { $resumeRecoveryTrace.trace[-1].observationAfter } else { $null }
    $arrivalAfterResumeRecovery = ($moveReceiptStep.Count -eq 1 -and $resumeRecoveryTrace.termination.completedByProvider -and $null -ne $finalResumeObservation -and [string]$finalResumeObservation.state.location.currentSettlementId -ceq [string]$moveReceiptStep[0].actionReceipt.state.location.targetSettlementId)
    $unlistedResumeRecoveryVerified = (
        $resumeRejection.Count -eq 1 -and $resumeRejection[0].actionAttempted -eq $false -and
        [bool]$resumeRejection[0].actionReceipt.noNativeActionSent -and $moveActions.Count -eq 1 -and
        $resumeFeedbackConsumed.Count -ge 1 -and $resumeRecoveryObserve.Count -ge 1 -and
        $staleObserveAgainRejectedWithoutNativeAction -and
        [string]$staleObserveRejection[0].observationBefore.state.location.currentSettlementId -ceq [string]$moveReceiptStep[0].actionReceipt.state.location.targetSettlementId -and
        $nativeTimeActions.Count -eq 0 -and
        [string]$resumeRejection[0].observationBefore.state.context.timeControlMode -ceq 'StoppablePlay' -and
        [string]$resumeRejection[0].observationAfter.state.context.timeControlMode -in @('StoppablePlay','Stop') -and
        $null -ne $finalResumeObservation -and $null -ne $moveReceiptStep -and
        [double]$finalResumeObservation.campaignDay -gt [double]$moveReceiptStep[0].actionReceipt.campaignDay
    )
    if (-not $unlistedResumeRecoveryVerified) { throw "The unsupported resume and stale post-arrival observeAgain proposals were safely rejected, surfaced as feedback, and recovered without clock-control Native actions: $($resumeRecoveryTrace | ConvertTo-Json -Depth 8 -Compress)" }

    $priorInvalidDecision = $env:CHRONICLE_TEST_INVALID_DECISION
    $env:CHRONICLE_TEST_INVALID_DECISION = '1'
    try {
        $invalidOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-invalid-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $invalidExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorInvalidDecision) { Remove-Item Env:CHRONICLE_TEST_INVALID_DECISION -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_INVALID_DECISION = $priorInvalidDecision }
    }
    $unsafeActionRejected = ($invalidExitCode -ne 0 -and $invalidOutput -match 'allowlist')
    if (-not $unsafeActionRejected) { throw "Unsafe provider action rejection check failed (exit=$invalidExitCode, message=$($invalidOutput -match 'allowlist')): $invalidOutput" }
    $priorInvalidDecision = $env:CHRONICLE_TEST_INVALID_DECISION
    $env:CHRONICLE_TEST_INVALID_DECISION = 'advance'
    try {
        $harnessClockOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 1 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-clock-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $harnessClockExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorInvalidDecision) { Remove-Item Env:CHRONICLE_TEST_INVALID_DECISION -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_INVALID_DECISION = $priorInvalidDecision }
    }
    $harnessClockRejected = ($harnessClockExitCode -ne 0 -and $harnessClockOutput -match 'Harness-only deterministic time step')
    if (-not $harnessClockRejected) { throw "Harness-only advance boundary check failed: $harnessClockOutput" }
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'observationLoop'
    try {
        $loopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 2 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $loopExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($loopExitCode -ne 0) { throw "Agent decision loop failed: $loopOutput" }
    $trace = $loopOutput | ConvertFrom-Json
    $first = $trace.trace[0]
    $second = $trace.trace[1]
    $observationLoopVerified = ($trace.trace.Count -eq 2 -and $first.decision.action -eq 'state' -and $first.actionReceipt.status -eq 'completed' -and $second.decision.action -eq 'mapPartyTargets' -and $second.actionReceipt.status -eq 'completed')
    $decisionTimingCaptured = ($trace.initialObservation.startedUtc -and $trace.initialObservation.completedUtc -and
        $first.timing.providerStartedUtc -and $first.timing.providerCompletedUtc -and
        $first.timing.actionStartedUtc -and $first.timing.actionCompletedUtc -and $first.timing.actionElapsedMilliseconds -ge 0 -and
        $first.timing.observationStartedUtc -and $first.timing.observationCompletedUtc -and $first.timing.observationElapsedMilliseconds -ge 0)
    $receiptForwarded = ($second.previousActionReceipt.commandId -eq $first.actionReceipt.commandId -and $second.previousActionReceipt.action -eq $first.actionReceipt.action -and $second.previousActionReceipt.status -eq $first.actionReceipt.status)
    $priorProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
    $env:CHRONICLE_TEST_PROVIDER_MODE = 'doneSignal'
    try {
        $doneOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop -DecisionProviderPath $provider -MaxDecisions 4 -TimeoutSeconds $TimeoutSeconds -CommandPrefix ('loop-done-' + [Guid]::NewGuid().ToString('N')) 2>&1 | Out-String
        $doneExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $priorProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_TEST_PROVIDER_MODE = $priorProviderMode }
    }
    if ($doneExitCode -ne 0) { throw "Agent loop did not stop on the provider's explicit goal-complete signal: $doneOutput" }
    $doneTrace = $doneOutput | ConvertFrom-Json
    $doneSignalVerified = ($doneTrace.trace.Count -eq 2 -and $doneTrace.actionsExecuted -eq 1 -and $doneTrace.termination.completedByProvider -and $doneTrace.termination.reason -eq 'provider-stop' -and -not $doneTrace.trace[1].actionExecuted -and $doneTrace.trace[1].decision.done)
    $stop = Invoke-AgentCli 'stop'
    $fixtureHashAfter = (Get-FileHash $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        ProviderKind = 'deterministic-test-only'
        ProcessId = $start.session.processId
        DecisionCount = @($trace.trace).Count
        ObservationActionObservationVerified = $observationLoopVerified
        FirstDecision = $first.decision.action
        SecondDecision = $second.decision.action
        PreviousActionReceiptForwarded = $receiptForwarded
        DecisionTimingCaptured = $decisionTimingCaptured
        UnicodeHeroNameRoundTripVerified = $unicodeRoundTripVerified
        ObserveAgainPolicySeparatesNaturalTimeFromStoppedEncounter = $observeAgainPolicyVerified
        ExplicitGoalStopHonoredWithoutIssuingAnotherAction = $doneSignalVerified
        GoalStopTrace = $doneTrace.trace
        GoalAndActionCatalogForwarded = $goalAndCatalogForwarded
        ScopedActionRejected = $scopedActionRejected
        DynamicActionCatalogRecoveryVerified = $dynamicActionRecoveryVerified
        DynamicActionRecoveryTrace = $recoveryTrace.trace
        StaleOfferRecoveryVerified = $staleOfferRecoveryVerified
        StaleOfferBlockedWithoutNativeMutation = $staleOfferBlockedWithoutMutation
        StaleOfferRecoveryTrace = $staleOfferTrace.trace
        UnlistedResumeRejectedWithoutNativeAction = $unlistedResumeRecoveryVerified
        StaleObserveAgainRejectedWithoutNativeAction = $staleObserveAgainRejectedWithoutNativeAction
        UnlistedResumeRecoveryTrace = $resumeRecoveryTrace.trace
        DecisionContextTrace = $contextTrace.trace
        UnsafeActionRejected = $unsafeActionRejected
        HarnessAdvanceRejected = $harnessClockRejected
        FixtureUnchanged = $fixtureHashBefore -eq $fixtureHashAfter
        ProcessStopped = $stop.processStopped
        Trace = $trace.trace
    }
    $result.Passed = ($result.DecisionCount -eq 2 -and $observationLoopVerified -and $receiptForwarded -and $decisionTimingCaptured -and $unicodeRoundTripVerified -and $observeAgainPolicyVerified -and $doneSignalVerified -and $goalAndCatalogForwarded -and $scopedActionRejected -and $dynamicActionRecoveryVerified -and $staleOfferRecoveryVerified -and $unlistedResumeRecoveryVerified -and $unsafeActionRejected -and $harnessClockRejected -and $result.FixtureUnchanged -and $result.ProcessStopped)
    $result | ConvertTo-Json -Depth 12
    if (-not $result.Passed) { exit 1 }
}
finally {
    if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' | Out-Null } catch { } }
}
