[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [ValidateRange(5,30)][int]$FrameRate = 10,
    [switch]$ArrivalLoop,
    [switch]$RecruitmentLoop,
    [switch]$RoadsideBanditNegotiationLoop,
    [switch]$SupplyManagementLoop,
    [switch]$AgentHostRuntime
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$loop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Agent-OpenAICompatibleProvider.ps1'
$videoLibrary = Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1'
$documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documentsPath)) { throw 'Windows Documents directory could not be resolved for the live-model fixture.' }
$documentsRoot = Join-Path $documentsPath 'Mount and Blade II Bannerlord'
$savePath = Join-Path $documentsRoot "Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $documentsRoot 'AgentRuns\ChronicleAgent\session.json'

if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) {
    throw 'Refusing to start a live-model Campaign test while any Bannerlord client is already running.'
}
if (@($ArrivalLoop, $RecruitmentLoop, $RoadsideBanditNegotiationLoop, $SupplyManagementLoop | Where-Object { $_ }).Count -gt 1) { throw 'Select only one LiveModel test goal per run.' }
if ($AgentHostRuntime -and -not $SupplyManagementLoop) { throw 'AgentHostRuntime is currently limited to the frozen Native supply slice.' }
if ($RoadsideBanditNegotiationLoop -and -not $RecruitmentLoop) { throw 'RoadsideBanditNegotiationLoop requires RecruitmentLoop so the encounter resolves into the existing growth goal.' }
foreach ($setting in @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL','CHRONICLE_LLM_API_KEY','CHRONICLE_LLM_TIMEOUT_SECONDS','CHRONICLE_LLM_MAX_TOKENS','CHRONICLE_LLM_MAX_TOKEN_PARAMETER','CHRONICLE_LLM_REASONING_EFFORT','CHRONICLE_LLM_THINKING_MODE','CHRONICLE_LLM_TEMPERATURE','CHRONICLE_LLM_PROTOCOL')) {
    $configuredValue = [string][Environment]::GetEnvironmentVariable($setting, 'Process')
    if ([string]::IsNullOrWhiteSpace($configuredValue)) {
        $configuredValue = [string][Environment]::GetEnvironmentVariable($setting, 'User')
        if (-not [string]::IsNullOrWhiteSpace($configuredValue)) { [Environment]::SetEnvironmentVariable($setting, $configuredValue, 'Process') }
    }
    if ($setting -in @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL') -and [string]::IsNullOrWhiteSpace($configuredValue)) {
        throw "Live-model verification requires local $setting configuration; the value is never printed by this test."
    }
}
$configuredProtocol = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_PROTOCOL)) { 'openai-compatible' } else { [string]$env:CHRONICLE_LLM_PROTOCOL }
if ($configuredProtocol -ceq 'ollama-native') {
    $ollamaEndpoint = $null
    if (-not [Uri]::TryCreate([string]$env:CHRONICLE_LLM_BASE_URL, [UriKind]::Absolute, [ref]$ollamaEndpoint) -or -not $ollamaEndpoint.IsLoopback) {
        throw 'Ollama-native live-model preflight requires a loopback HTTP endpoint; no Campaign fixture was started.'
    }
    $ollamaTagsUri = [UriBuilder]::new($ollamaEndpoint)
    $ollamaTagsUri.Path = '/api/tags'
    try { $ollamaTags = Invoke-RestMethod -Uri $ollamaTagsUri.Uri -Method Get -TimeoutSec 5 }
    catch { throw "Configured local Ollama service is unreachable before Campaign launch (host=$($ollamaEndpoint.Host)); no fixture was started." }
    $availableLocalModels = @($ollamaTags.models | ForEach-Object { [string]$_.name })
    if ([string]$env:CHRONICLE_LLM_MODEL -notin $availableLocalModels) {
        throw "Configured local Ollama model '$($env:CHRONICLE_LLM_MODEL)' is not installed on the reachable service; no Campaign fixture was started."
    }
}
$sourceCommitOutput = & git.exe -C $PSScriptRoot rev-parse HEAD 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Live-model verification could not record the source commit.' }
$sourceCommit = ([string]($sourceCommitOutput | Out-String)).Trim()
if ([string]::IsNullOrWhiteSpace($sourceCommit)) { throw 'Live-model verification received an empty source commit identifier.' }
$sourceStatusOutput = & git.exe -C $PSScriptRoot status --short --untracked-files=no 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Live-model verification could not determine whether tracked source files were modified.' }
$sourceTrackedTreeClean = @($sourceStatusOutput | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0
if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw "Disposable AgentLoop fixture not found: $savePath" }
if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing to replace an existing Chronicle Agent session; stop or recover it before the live-model test.' }
if (-not $env:CHRONICLE_HARNESS_TEMP -or -not (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
    throw 'Live-model visual evidence requires the active Run-Harness TestResults temp directory.'
}

$runDirectory = Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP
$videoPath = Join-Path $runDirectory 'LiveModelWindow.mp4'
$contactSheetPath = Join-Path $runDirectory 'LiveModelWindow-contact.jpg'
$eventTracePath = Join-Path $runDirectory 'LiveModelWindow-events.jsonl'
$timelineIndexPath = Join-Path $runDirectory 'LiveModelWindow-timeline-index.json'
$engineFrameBeforePath = Join-Path $runDirectory 'LiveModelEngine-before.bmp'
$engineFrameAfterPath = Join-Path $runDirectory 'LiveModelEngine-after.bmp'
$engineFrameFailurePath = Join-Path $runDirectory 'LiveModelEngine-failure.bmp'
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$priorHarnessMode = $env:CHRONICLE_HARNESS_MODE
$priorModelTimeout = $env:CHRONICLE_LLM_TIMEOUT_SECONDS
$priorModelMaxTokens = $env:CHRONICLE_LLM_MAX_TOKENS
$sessionStarted = $false
$capture = $null
$captureResult = $null
$loopTrace = $null
$failure = $null
$start = $null
$stop = $null
$liveModelTrace = $null
$fixtureHashAfter = $null
$fixtureUnchanged = $false
$processStopped = $false
$failureEngineFrameCaptured = $false
$failureEvidenceError = $null
$supplySetup = $null
$supplyVerified = $null
$supplyVerification = $null
$completionContractBase64 = $null
$chosenSettlementId = ''
$chosenSettlementName = ''

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Write-LiveModelCaptureEvent(
    [string]$EventName,
    [string]$Utc,
    [string]$Action,
    [string]$CommandId,
    $State,
    $Receipt,
    $ActiveCapture,
    [string]$DecisionAction = ''
) {
    $eventUtc = if ([string]::IsNullOrWhiteSpace($Utc)) { (Get-Date).ToUniversalTime().ToString('O') } else { $Utc }
    $startUtc = [DateTimeOffset]::Parse([string]$ActiveCapture.StartedUtc).ToUniversalTime()
    $eventOffset = [DateTimeOffset]::Parse($eventUtc).ToUniversalTime()
    $stateContext = if ($State -and $State.context) { $State.context } else { $null }
    $event = [ordered]@{
        event = $EventName
        utc = $eventUtc
        offsetMilliseconds = [Math]::Round(($eventOffset - $startUtc).TotalMilliseconds, 2)
        commandId = $CommandId
        action = $Action
        decisionAction = $DecisionAction
        gameState = if ($stateContext) { [string]$stateContext.gameState } else { $null }
        menuId = if ($stateContext) { [string]$stateContext.menuId } else { $null }
        partyScreenMode = if ($State -and $State.partyScreen) { [string]$State.partyScreen.mode } else { $null }
        inventoryMode = if ($State -and $State.inventoryScreen) { [string]$State.inventoryScreen.mode } else { $null }
        campaignDay = if ($Receipt) { $Receipt.campaignDay } elseif ($State) { $State.campaignDay } else { $null }
    }
    Add-Content -LiteralPath $eventTracePath -Value ($event | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
}

function Capture-EngineFrame([string]$Name) {
    $temporaryPath = Join-Path $env:CHRONICLE_HARNESS_TEMP ($Name + '.bmp')
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    $still = Invoke-AgentCli 'captureFrame' @('-OutputPath', $temporaryPath, '-CommandId', ($Name + '-' + [Guid]::NewGuid().ToString('N'))) 15
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $temporaryPath) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($still.status -ne 'completed' -or -not (Test-Path -LiteralPath $temporaryPath) -or (Get-Item -LiteralPath $temporaryPath).Length -lt 4096) {
        throw "Native engine frame '$Name' was not captured."
    }
    $destination = switch ($Name) {
        'LiveModelEngine-before' { $engineFrameBeforePath; break }
        'LiveModelEngine-after' { $engineFrameAfterPath; break }
        'LiveModelEngine-failure' { $engineFrameFailurePath; break }
        default { throw "Unknown LiveModel engine-frame label '$Name'." }
    }
    Move-Item -LiteralPath $temporaryPath -Destination $destination -Force
    return $destination
}

try {
    . $videoLibrary
    Set-Content -LiteralPath $eventTracePath -Value '' -Encoding UTF8
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $sessionStarted = $true
    $baseline = Invoke-AgentCli 'state'
    if ($baseline.status -ne 'completed' -or $baseline.state.context.gameState -ne 'MapState' -or $baseline.state.location.currentSettlementId) {
        throw 'Live-model fixture must load into an unobstructed Campaign Map state.'
    }
    $null = Capture-EngineFrame 'LiveModelEngine-before'
    $capture = Start-ChronicleWindowVideoCapture -ProcessId ([int]$start.session.processId) -OutputPath $videoPath -FrameRate $FrameRate
    $modelRunStartedUtc = [string]$capture.StartedUtc
    Write-LiveModelCaptureEvent 'capture-start' $capture.StartedUtc 'capture' $null $baseline.state $baseline $capture

    if ($SupplyManagementLoop) {
        $target = @($baseline.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile -and -not $_.underSiege -and [double]$_.distance -gt 1.0 } | Sort-Object { [double]$_.distance } | Select-Object -First 1)
        if ($target.Count -ne 1) { throw 'Supply fixture preparation found no safe, visible Native Town target.' }
        $chosenSettlementId = [string]$target[0].id
        $chosenSettlementName = [string]$target[0].name
        $move = Invoke-AgentCli 'move' @('-SettlementId', $chosenSettlementId, '-CommandId', ('supply-setup-move-' + [Guid]::NewGuid().ToString('N')))
        if ($move.status -ne 'completed' -or [string]$move.state.location.targetSettlementId -cne $chosenSettlementId) { throw 'Supply fixture Native movement did not accept the currently visible safe Town.' }
        $arrivalDeadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $arrival = $null
        while ([DateTime]::UtcNow -lt $arrivalDeadline) {
            $arrival = Invoke-AgentCli 'state' @('-CommandId', ('supply-setup-arrival-' + [Guid]::NewGuid().ToString('N')))
            if ([string]$arrival.state.location.currentSettlementId -ceq $chosenSettlementId -and [string]$arrival.state.context.menuId -eq 'town') { break }
            if ([bool]$arrival.state.context.encounterActive) { throw 'An encounter interrupted deterministic supply-scene setup; this is not a model trial.' }
            if (-not [bool]$arrival.state.party.isMoving) { throw 'Native movement stopped before the supply-scene Town was reached.' }
            if ([string]$arrival.state.context.timeControlMode -notin @('StoppablePlay','UnstoppableFastForward')) { throw 'Campaign time stopped during deterministic supply-scene setup.' }
            Start-Sleep -Seconds 1
        }
        if (-not $arrival -or [string]$arrival.state.location.currentSettlementId -cne $chosenSettlementId -or [string]$arrival.state.context.menuId -ne 'town') { throw 'Deterministic supply-scene setup timed out before reaching the Town menu.' }

        $setupGold = [int]$arrival.state.economy.gold
        $recruitReceipts = [System.Collections.Generic.List[object]]::new()
        while ([int]$arrival.state.party.members -lt 6) {
            $offers = Invoke-AgentCli 'recruitOptions' @('-CommandId', ('supply-setup-offers-' + [Guid]::NewGuid().ToString('N')))
            if ($offers.status -ne 'completed') { throw 'Native volunteer offers were not available to establish the fixed six-person supply fixture.' }
            $offer = @($offers.data.offers | Where-Object { $_.available -and [int]$_.cost -le [int]$arrival.state.economy.gold } | Sort-Object { [int]$_.cost }, { [int]$_.slot } | Select-Object -First 1)
            if ($offer.Count -ne 1) { throw 'Native Town volunteers could not establish the fixed six-person supply fixture.' }
            $recruit = Invoke-AgentCli 'recruit' @('-OwnerId', [string]$offer[0].ownerId, '-TroopId', [string]$offer[0].troopId, '-VolunteerSlot', [string]$offer[0].slot, '-CommandId', ('supply-setup-recruit-' + [Guid]::NewGuid().ToString('N')))
            $arrival = Invoke-AgentCli 'state' @('-CommandId', ('supply-setup-post-recruit-' + [Guid]::NewGuid().ToString('N')))
            if ($recruit.status -ne 'completed' -or -not [bool]$recruit.data.verified -or [int]$arrival.state.party.members -ne ([int]$recruitReceipts.Count + [int]$baseline.state.party.members + 1) -or [int]$arrival.state.economy.gold -ne ($setupGold - [int]$offer[0].cost)) {
                throw 'Native recruitment did not match the fixed supply-fixture setup receipt.'
            }
            $setupGold -= [int]$offer[0].cost
            $recruitReceipts.Add([pscustomobject]@{ Cost = [int]$offer[0].cost; Receipt = $recruit.data })
        }
        if ([int]$arrival.state.party.members -ne 6 -or [int]$arrival.state.economy.gold -ne 900 -or [Math]::Abs([double]$arrival.state.party.food - 0.95) -gt 0.01 -or [int]$arrival.state.party.foodInventory -ne 0 -or [Math]::Abs([double]$arrival.state.party.foodChange - (-0.3)) -gt 0.01 -or [int]$arrival.state.party.dailyWage -ne 10 -or [int]$arrival.dailyTickCount -ne 2) {
            throw 'Native prelude did not establish the measured six-member supply baseline; no state will be injected to force it.'
        }
        $baseline = $arrival
        $supplySetup = [ordered]@{
            TargetSettlementId = $chosenSettlementId
            TargetSettlementName = $chosenSettlementName
            CampaignDay = [double]$arrival.campaignDay
            DailyTickCount = [int]$arrival.dailyTickCount
            Members = [int]$arrival.state.party.members
            Gold = [int]$arrival.state.economy.gold
            Food = [double]$arrival.state.party.food
            FoodInventory = [int]$arrival.state.party.foodInventory
            FoodChange = [double]$arrival.state.party.foodChange
            DailyWage = [int]$arrival.state.party.dailyWage
            NativeRecruitmentReceipts = @($recruitReceipts)
            IsHarnessSetupNotModelEvidence = $true
        }
        Write-LiveModelCaptureEvent 'supply-fixture-prepared' ([DateTime]::UtcNow.ToString('O')) 'nativeSetup' $null $baseline.state $supplySetup $capture
    }

    if ($RoadsideBanditNegotiationLoop) {
        $goal = 'Autonomously recruit one currently affordable local volunteer from a safe Native Settlement. Select a target from current nearbySettlements; issue one Native move. A hostile looter may interrupt travel. If a current Native bandit conversation appears and the observed bandit side is stronger than the player side, choose the currently visible non-fight compromise option; never choose to start a tactical battle in this one-member growth slice. After selecting compromise, do not use dialogueSelect unless the fresh observation contains a clickable option. When the bandit conversation has no clickable options, call barterOptions first to check whether the Native Safe Passage BarterVM is ready. Only if that read is rejected and the fresh Native observation still has an active no-option conversation should you call dialogueContinue once, then query barterOptions again; never repeat Continue without rechecking. Only after barterOptions returns the Safe Passage context may you call barterAutoBalance; submit barterOffer only if the Native quote is enabled and the remaining Gold stays positive. After accepting safe passage, re-observe the Campaign Map because the Native party may be Holding with no target; select a newly observed safe settlement and move again if needed. Do not use pause/resume/fastForward, do not reuse a stale target, and do not invent offers. At a settlement, use the currently enabled recruit_volunteers option, choose one affordable offer within capacity, recruit it with ConfirmPartySizeWarning=false, verify Party +1 and exact Gold cost, then stop.'
        $maxDecisions = 36
        $maxElapsedSeconds = 600
        $allowedActions = 'mapSettlementTargets,move,dialogueSelect,dialogueContinue,barterOptions,barterAutoBalance,barterOffer,barterCancel,recruitOptions,recruit'
        $env:CHRONICLE_LLM_TIMEOUT_SECONDS = '180'
        $env:CHRONICLE_LLM_MAX_TOKENS = '768'
    }
    elseif ($RecruitmentLoop) {
        $goal = 'Autonomously recruit one affordable local volunteer. Choose one safe target from current Native nearbySettlements observation; query mapSettlementTargets only if the current observation does not provide enough target information. The target must not be the current settlement, hostile, or under siege. Issue one move only. While still moving, use observeAgain with waitSeconds 5; never send move again or change clock controls. Once a fresh Native observation shows arrival, inspect the current settlement menu. If recruit_volunteers is currently available, call recruitOptions. Select one currently available offer that is affordable and fits party capacity; call recruit with its observed ownerId, troopId and slot, and ConfirmPartySizeWarning=false. After the Native receipt and fresh state show members increased by one and gold decreased by that offer cost, return done. If the current settlement has no eligible offer, use only newly observed safe settlement targets to replan; never invent inventory or force an over-capacity choice.'
        $maxDecisions = 24
        $maxElapsedSeconds = 600
        $allowedActions = 'mapSettlementTargets,move,recruitOptions,recruit'
        $env:CHRONICLE_LLM_TIMEOUT_SECONDS = '180'
        $env:CHRONICLE_LLM_MAX_TOKENS = '512'
    }
    elseif ($SupplyManagementLoop) {
        $goal = 'Supply objective: keep this six-member MainParty at Sargot supplied for three real Campaign daily ticks. Starting dailyTickCount is 2; the required target is tick 5. Starting Food is 0.95 and FoodChange is -0.3/day. The measured one-unit Native baseline is: one cheapest food item costs 9, Food becomes 1.95, and after three daily ticks Food is 1.05. Therefore buy exactly one unit total, using the current lowest-priced affordable Native foodOptions offer; never reopen Trade after the first successful tradeConfirm, even if you think extra food is safer. Keep the party size six. Use only currently enabled OptionIds. menuSelect accepts only OptionId and binds the current Native menu. First: select trade, query foodOptions, and buy one unit. A successful provision only drafts the transfer; while the Trade InventoryState is open, select the currently listed tradeConfirm exactly once to commit it. Do not wait, request observeAgain, or act before the committed tradeConfirm receipt. Only after completed tradeConfirm, select town_wait, then request rest Days=3. Once rest is accepted, the Host passively polls Native state and selects the currently enabled wait_leave option exactly once when tick 5 is reached; do not issue more waits, trades, or time-control actions during that pending Native rest. Continue from the fresh Native state returned by the Host. Return done only after fresh state shows Town menu, six members, Gold >= 861, and Food >= 1.0. If any action is rejected, use the new state and available action catalog; never reuse an unavailable action. Never call explicit clock controls or claim unverified outcomes.'
        $maxDecisions = 24
        $maxElapsedSeconds = 300
        $allowedActions = 'menuSelect,foodOptions,provision,tradeConfirm,rest'
        $completionContract = [ordered]@{
            schemaVersion = 1
            contractId = 'sargot-three-day-food-v1'
            conditions = @(
                [ordered]@{ id='party-size'; path='state.party.members'; operator='eq'; expected=6 }
                [ordered]@{ id='daily-ticks'; path='dailyTickCount'; operator='gte'; expected=([int]$supplySetup.DailyTickCount + 3) }
                [ordered]@{ id='gold-minimum'; path='state.economy.gold'; operator='gte'; expected=861 }
                [ordered]@{ id='food-minimum'; path='state.party.food'; operator='gte'; expected=1.0 }
                [ordered]@{ id='town-location'; path='state.location.currentSettlementId'; operator='eq'; expected=[string]$chosenSettlementId }
                [ordered]@{ id='town-menu'; path='state.context.menuId'; operator='eq'; expected='town' }
                [ordered]@{ id='campaign-map'; path='state.context.gameState'; operator='eq'; expected='MapState' }
            )
        }
        $completionContractJson = $completionContract | ConvertTo-Json -Depth 8 -Compress
        $completionContractBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($completionContractJson))
        $env:CHRONICLE_LLM_TIMEOUT_SECONDS = '180'
        $env:CHRONICLE_LLM_MAX_TOKENS = '256'
    }
    elseif ($ArrivalLoop) {
        $goal = 'First query mapSettlementTargets. Then choose the nearest observed safe target (not hostile, not under siege, not the current settlement) and issue one move. While party.isMoving toward that target and currentSettlementId differs, use observeAgain with waitSeconds 5; do not send move again or use clock controls. When nativeMoveArrival.status is arrived, return done immediately and issue no further game action.'
        $env:CHRONICLE_LLM_TIMEOUT_SECONDS = '180'
        # The four-step arrival loop emits compact JSON; reserve only 256 completion tokens to keep the 4K context available for observed state.
        $env:CHRONICLE_LLM_MAX_TOKENS = '256'
        $maxDecisions = 30
        $maxElapsedSeconds = 600
        $allowedActions = 'mapSettlementTargets,move'
    }
    else {
        $goal = 'This is a strict three-decision state machine. If previousActionReceipt is null, choose mapSettlementTargets. If previousActionReceipt.action is mapSettlementTargets and previousActionReceipt.status is completed, choose exactly one target from its receipt whose hostile=false and underSiege=false and issue one Native move order to that id. If previousActionReceipt.action is move and previousActionReceipt.status is completed, return done immediately; do not query or move again. Do not skip, repeat, or change Campaign time mode explicitly.'
        $maxDecisions = 3
        $maxElapsedSeconds = 0
        $allowedActions = 'mapSettlementTargets,move'
    }
    $loopExitCode = 0
    if ($AgentHostRuntime) {
        $agentHostDll = Join-Path $PSScriptRoot 'AgentHost\bin\Release\net8.0\ChronicleAgentHost.dll'
        $supplyRequest = [ordered]@{
            runId = ('agenthost-supply-' + [Guid]::NewGuid().ToString('N'))
            goal = $goal
            targetSettlementId = $chosenSettlementId
            maxDecisions = $maxDecisions
            maxElapsedSeconds = $maxElapsedSeconds
            allowedActionNames = @($allowedActions.Split(',') | ForEach-Object { $_.Trim() })
            completionContract = $completionContractJson | ConvertFrom-Json
        }
        $hostStartInfo = [Diagnostics.ProcessStartInfo]::new()
        $hostStartInfo.FileName = (Get-Command dotnet -ErrorAction Stop).Source
        $hostStartInfo.Arguments = '"{0}" --supply-loop' -f $agentHostDll
        $hostStartInfo.UseShellExecute = $false
        $hostStartInfo.CreateNoWindow = $true
        $hostStartInfo.RedirectStandardInput = $true
        $hostStartInfo.RedirectStandardOutput = $true
        $hostStartInfo.RedirectStandardError = $true
        $hostProcess = [Diagnostics.Process]::new()
        $hostProcess.StartInfo = $hostStartInfo
        if (-not $hostProcess.Start()) { throw 'Could not start the local Agent Host supply loop.' }
        $hostStdoutTask = $hostProcess.StandardOutput.ReadToEndAsync()
        $hostStderrTask = $hostProcess.StandardError.ReadToEndAsync()
        $hostProcess.StandardInput.WriteLine(($supplyRequest | ConvertTo-Json -Depth 12 -Compress))
        $hostProcess.StandardInput.Close()
        $hostTimeoutMilliseconds = [int](($maxElapsedSeconds + 60) * 1000)
        if (-not $hostProcess.WaitForExit($hostTimeoutMilliseconds)) {
            try { $hostProcess.Kill() } catch { }
            throw 'Local Agent Host supply loop exceeded the bounded process timeout.'
        }
        $output = $hostStdoutTask.GetAwaiter().GetResult()
        $hostStderr = $hostStderrTask.GetAwaiter().GetResult()
        $loopExitCode = [int]$hostProcess.ExitCode
        if ($loopExitCode -ne 0 -and [string]::IsNullOrWhiteSpace($output)) { $output = $hostStderr }
    }
    else {
        $loopArguments = @('-DecisionProviderPath', $provider, '-Goal', $goal, '-AllowedActionNames', $allowedActions, '-MaxDecisions', [string]$maxDecisions, '-MaxElapsedSeconds', [string]$maxElapsedSeconds, '-TimeoutSeconds', [string]$TimeoutSeconds, '-CommandPrefix', ('live-model-' + [Guid]::NewGuid().ToString('N')))
        if ($completionContractBase64) { $loopArguments += @('-CompletionContractBase64', $completionContractBase64) }
        if ($RoadsideBanditNegotiationLoop) { $loopArguments += '-HarnessPrepareSafePassageAfterMove' }
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $loop @loopArguments 2>&1 | Out-String
        $loopExitCode = $LASTEXITCODE
    }
    if ($loopExitCode -ne 0) {
        try { $loopTrace = $output | ConvertFrom-Json } catch { }
        $loopError = if ($loopTrace -and $loopTrace.error) { [string]$loopTrace.error } else { [string]$output }
        if ($loopError.Length -gt 1200) { $loopError = $loopError.Substring(0, 1200) + '...[truncated; full structured trace retained separately]' }
        $runnerName = if ($AgentHostRuntime) { 'Local Agent Host' } else { 'PowerShell decision loop' }
        throw "Real-model decision loop failed in ${runnerName}: $loopError"
    }
    $loopTrace = $output | ConvertFrom-Json
    if ($loopTrace.status -eq 'failed') { throw "Real-model decision loop failed: $($loopTrace.error)" }

    $steps = @($loopTrace.trace)
    $safePassageRoute = $null
    if ($RoadsideBanditNegotiationLoop) {
        $banditFixture = @($loopTrace.harnessEvents | Where-Object { $_.kind -eq 'native-safe-passage-bandit-prepared' } | Select-Object -First 1)
        $banditConversation = @($steps | Where-Object {
            [bool]$_.observationBefore.state.context.encounterActive -and
            [string]$_.observationBefore.state.context.encounteredPartyId -ceq [string]$banditFixture[0].partyId -and
            @($_.observationBefore.state.context.conversation.options | Where-Object { $_.clickable }).Count -gt 0
        } | Select-Object -First 1)
        $peacefulDialogue = @($steps | Where-Object { $_.decision.action -eq 'dialogueSelect' } | Select-Object -First 1)
        if ($banditFixture.Count -ne 1 -or $banditFixture[0].banditStrength -le $banditFixture[0].requiredBanditStrength -or $banditConversation.Count -ne 1 -or $peacefulDialogue.Count -ne 1) {
            throw 'A measured hostile Native Safe Passage fixture did not reach the live model as a current encounter dialogue with a player response.'
        }
        $selectedDialogueOption = @($peacefulDialogue[0].observationBefore.state.context.conversation.options | Where-Object { [string]$_.id -ceq [string]$peacefulDialogue[0].decision.arguments.OptionId -and $_.clickable } | Select-Object -First 1)
        if ($selectedDialogueOption.Count -ne 1 -or [string]$peacefulDialogue[0].observationBefore.state.context.encounteredPartyId -cne [string]$banditFixture[0].partyId -or [string]$selectedDialogueOption[0].text -notmatch '\u4E24\u5168\u5176\u7F8E|\u529E\u6CD5|\u89E3\u51B3') {
            throw 'The model did not select the current Native non-combat compromise option from the observed hostile encounter.'
        }
        $safePassageBarterOptions = @($steps | Where-Object { $_.decision.action -eq 'barterOptions' -and $_.actionReceipt.status -eq 'completed' -and $_.actionReceipt.data.contextInitializer -eq 'InitializeSafePassageBarterContext' } | Select-Object -First 1)
        $safePassageAutoBalance = @($steps | Where-Object { $_.decision.action -eq 'barterAutoBalance' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
        $safePassageOffer = @($steps | Where-Object { $_.decision.action -eq 'barterOffer' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
        $safePassageGoldOffer = @()
        if ($safePassageAutoBalance.Count -eq 1) {
            $safePassageGoldOffer = @($safePassageAutoBalance[0].actionReceipt.data.updatedOptions.candidates | Where-Object { $_.nativeType -eq 'gold_barterable' -and $_.list -eq 'rightGold' -and $_.isOffered } | Select-Object -First 1)
        }
        $nativeClockActionsDuringRecovery = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -in @('pause','resume','fastForward') })
        if ($safePassageBarterOptions.Count -ne 1 -or $safePassageAutoBalance.Count -ne 1 -or -not [bool]$safePassageAutoBalance[0].actionReceipt.data.autoBalanced -or
            $safePassageOffer.Count -ne 1 -or -not [bool]$safePassageOffer[0].actionReceipt.data.accepted -or [int]$safePassageOffer[0].observationAfter.state.economy.gold -le 0) {
            throw 'The model did not use the current Native Safe Passage BarterVM, auto-balance its live quote, and complete an affordable non-combat offer.'
        }
        if ($safePassageGoldOffer.Count -ne 1 -or [int]$safePassageGoldOffer[0].currentAmount -le 0 -or $nativeClockActionsDuringRecovery.Count -gt 0 -or
            [string]$safePassageOffer[0].observationBefore.state.context.timeControlMode -cne 'Stop' -or [string]$safePassageOffer[0].observationAfter.state.context.timeControlMode -cne 'Stop') {
            throw 'Safe Passage must use the current positive Native gold quote, submit it while the Native encounter clock is stopped, and never execute an explicit time-control action.'
        }
        $safePassageRoute = [ordered]@{
            BanditFixture = $banditFixture[0]
            Conversation = $banditConversation[0].observationBefore.state.context.conversation
            SelectedOption = [ordered]@{ id = [string]$peacefulDialogue[0].decision.arguments.OptionId; text = [string]$selectedDialogueOption[0].text }
            BarterAutoBalance = $safePassageAutoBalance[0].actionReceipt.data
            OfferResult = $safePassageOffer[0].actionReceipt.data
            OfferedDenars = [int]$safePassageGoldOffer[0].currentAmount
            GoldAfterOffer = [int]$safePassageOffer[0].observationAfter.state.economy.gold
            NativeClockActions = $nativeClockActionsDuringRecovery.Count
        }
    }
    foreach ($step in $steps) {
        $stepAction = if ($step.decision.done -eq $true) { 'providerDone' } elseif ($step.decision.observeAgain -eq $true) { 'observeAgain' } else { [string]$step.decision.action }
        $beforeState = if ($step.observationBefore.state) { $step.observationBefore.state } else { $baseline.state }
        Write-LiveModelCaptureEvent 'provider-response' $step.timing.providerCompletedUtc 'providerDecision' $null $beforeState $null $capture $stepAction
        if ($step.actionExecuted) {
            $afterState = if ($step.observationAfter.state) { $step.observationAfter.state } else { $beforeState }
            Write-LiveModelCaptureEvent 'native-action' $step.timing.actionCompletedUtc ([string]$step.actionReceipt.action) ([string]$step.actionReceipt.commandId) $afterState $step.actionReceipt $capture $stepAction
            Write-LiveModelCaptureEvent 'post-action-observation' $step.timing.observationCompletedUtc 'state' ([string]$step.actionReceipt.commandId) $afterState $step.actionReceipt $capture $stepAction
        }
        elseif ($step.control -and $step.observationAfter) {
            Write-LiveModelCaptureEvent 'scheduler-wait' $step.timing.schedulerWaitCompletedUtc 'boundedObserveAgain' $null $beforeState $null $capture $stepAction
            Write-LiveModelCaptureEvent 'post-wait-observation' $step.timing.observationCompletedUtc 'state' $null $step.observationAfter.state $null $capture $stepAction
        }
    }

    if ($SupplyManagementLoop) {
        $chosenId = $chosenSettlementId
        $chosenTarget = @([pscustomobject]@{ id = $chosenSettlementId; name = $chosenSettlementName })
        $observedTargets = @($chosenTarget)
        $targetSource = 'Native prelude; excluded from model actions'
        $targetQueries = @()
        $moveSteps = @()
        $observeSteps = @($steps | Where-Object { $_.control.kind -eq 'bounded-observe-again' -and -not $_.actionExecuted -and $_.observationAfter.status -eq 'completed' })
        $preNativeTravelReobservations = @()
        $nativeReadObservationsAfterMove = @()
        $arrivalConfirmed = ([string]$baseline.state.location.currentSettlementId -ceq $chosenId)
        $campaignDayAdvancedDuringTravel = $false

        $tradeEntrySteps = @($steps | Where-Object { $_.decision.action -eq 'menuSelect' -and [string]$_.decision.arguments.OptionId -eq 'trade' -and $_.actionReceipt.status -eq 'completed' })
        $tradeEntry = @($tradeEntrySteps | Select-Object -First 1)
        $foodReadSteps = @($steps | Where-Object { $_.decision.action -eq 'foodOptions' -and $_.actionReceipt.status -eq 'completed' })
        $foodRead = @($foodReadSteps | Select-Object -First 1)
        $provisionSteps = @($steps | Where-Object { $_.decision.action -eq 'provision' -and $_.actionReceipt.status -eq 'completed' })
        $provisionStep = @($provisionSteps | Select-Object -First 1)
        $tradeCommitSteps = @($steps | Where-Object { $_.decision.action -eq 'tradeConfirm' -and $_.actionReceipt.status -eq 'completed' })
        $tradeCommit = @($tradeCommitSteps | Select-Object -First 1)
        $waitEntrySteps = @($steps | Where-Object { $_.decision.action -eq 'menuSelect' -and [string]$_.decision.arguments.OptionId -eq 'town_wait' -and $_.actionReceipt.status -eq 'completed' })
        $waitEntry = @($waitEntrySteps | Select-Object -First 1)
        $restSteps = @($steps | Where-Object { $_.decision.action -eq 'rest' -and $_.actionExecuted -and $_.actionReceipt.status -in @('accepted','completed') })
        $restStep = @($restSteps | Select-Object -First 1)
        $hostRestMonitorSteps = @($steps | Where-Object { $_.control.kind -eq 'host-await-native-rest' })
        $hostRestMonitor = @($hostRestMonitorSteps | Select-Object -First 1)
        $hostRestLeaveSteps = @($steps | Where-Object { $_.decision.hostExecution -eq 'finish-accepted-native-rest' -and $_.actionReceipt.action -eq 'menuSelect' -and $_.actionReceipt.status -eq 'completed' })
        $hostRestLeaveOption = @()
        if ($hostRestLeaveSteps.Count -eq 1) { $hostRestLeaveOption = @($hostRestLeaveSteps[0].observationBefore.state.availableMenuOptions | Where-Object { $_.id -eq 'wait_leave' -and $_.available -and $_.enabled } | Select-Object -First 1) }
        $leaveWaitSteps = @($steps | Where-Object { $_.decision.action -eq 'menuSelect' -and [string]$_.decision.arguments.OptionId -eq 'wait_leave' -and $_.actionReceipt.status -eq 'completed' })
        $leaveWait = @($leaveWaitSteps | Select-Object -Last 1)
        $latestObservation = @($steps | Where-Object { $_.observationBefore -and $_.observationBefore.state } | Select-Object -Last 1)
        $finalObservation = if ($latestObservation.Count -eq 1) { $latestObservation[0].observationBefore } else { $baseline }
        $nativeClockActions = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -in @('advance','pause','resume','fastForward') })
        $rejectedSteps = @($steps | Where-Object {
            $_.control.kind -eq 'decision-rejected-before-native' -or
            ($_.actionAttempted -and [string]$_.actionReceipt.status -eq 'rejected')
        })
        $rejectedStatePreserved = @($rejectedSteps | ForEach-Object {
            $before = $_.observationBefore
            $after = if ($_.control.kind -eq 'decision-rejected-before-native') { $_.observationAfter } else { $_.actionReceipt }
            if (-not $before -or -not $after -or -not $before.state -or -not $after.state) { $false }
            else {
                $beforeState = $before.state
                $afterState = $after.state
                ([Math]::Abs([double]$before.campaignDay - [double]$after.campaignDay) -le 0.000001 -and
                    [int]$before.dailyTickCount -eq [int]$after.dailyTickCount -and
                    [int]$beforeState.economy.gold -eq [int]$afterState.economy.gold -and
                    [int]$beforeState.party.members -eq [int]$afterState.party.members -and
                    [double]$beforeState.party.food -eq [double]$afterState.party.food -and
                    [int]$beforeState.party.foodInventory -eq [int]$afterState.party.foodInventory -and
                    [string]$beforeState.location.currentSettlementId -ceq [string]$afterState.location.currentSettlementId -and
                    [string]$beforeState.location.targetSettlementId -ceq [string]$afterState.location.targetSettlementId -and
                    [string]$beforeState.context.gameState -ceq [string]$afterState.context.gameState -and
                    [string]$beforeState.context.menuId -ceq [string]$afterState.context.menuId -and
                    [string]$beforeState.context.timeControlMode -ceq [string]$afterState.context.timeControlMode)
            }
        })
        $rejectedActionsDidNotChangeWorld = ($rejectedStatePreserved.Count -eq $rejectedSteps.Count -and @($rejectedStatePreserved | Where-Object { -not $_ }).Count -eq 0)
        $selectedFoodOffer = @()
        $cheapestFoodOffer = @()
        $tradeOption = @()
        $waitOption = @()
        $leaveOption = @()
        if ($tradeEntry.Count -eq 1) { $tradeOption = @($tradeEntry[0].observationBefore.state.availableMenuOptions | Where-Object { $_.id -eq 'trade' -and $_.available -and $_.enabled } | Select-Object -First 1) }
        if ($waitEntry.Count -eq 1) { $waitOption = @($waitEntry[0].observationBefore.state.availableMenuOptions | Where-Object { $_.id -eq 'town_wait' -and $_.available -and $_.enabled } | Select-Object -First 1) }
        if ($leaveWait.Count -eq 1) { $leaveOption = @($leaveWait[0].observationBefore.state.availableMenuOptions | Where-Object { $_.id -eq 'wait_leave' -and $_.available -and $_.enabled } | Select-Object -First 1) }
        if ($foodRead.Count -eq 1 -and $provisionStep.Count -eq 1) {
            $selectedFoodOffer = @($foodRead[0].actionReceipt.data.offers | Where-Object { [string]$_.viewModelItemId -ceq [string]$provisionStep[0].decision.arguments.ItemViewModelId -and [bool]$_.isFood -and [bool]$_.isTransferable -and [int]$_.stock -ge [int]$provisionStep[0].decision.arguments.Amount -and [double]$_.inventoryLogicUnitPrice -le [int]$foodRead[0].observationBefore.state.economy.gold } | Select-Object -First 1)
            $cheapestFoodOffer = @($foodRead[0].actionReceipt.data.offers | Where-Object { [bool]$_.isFood -and [bool]$_.isTransferable -and [int]$_.stock -gt 0 -and [double]$_.inventoryLogicUnitPrice -le [int]$foodRead[0].observationBefore.state.economy.gold } | Sort-Object { [double]$_.inventoryLogicUnitPrice } | Select-Object -First 1)
        }
        $naturalTicksElapsed = [int]$finalObservation.dailyTickCount - [int]$supplySetup.DailyTickCount
        $providerStoppedAfterGoalAction = ([bool]$loopTrace.termination.completedByProvider -and [bool]$loopTrace.termination.goalVerified -and [bool]$steps[-1].decision.done)
        $supplyVerified = (
            $tradeEntrySteps.Count -eq 1 -and $tradeEntry.Count -eq 1 -and $tradeOption.Count -eq 1 -and [string]$tradeEntry[0].observationBefore.state.context.menuId -eq 'town' -and
            $foodReadSteps.Count -eq 1 -and
            $foodRead.Count -eq 1 -and [string]$foodRead[0].observationBefore.state.context.gameState -eq 'InventoryState' -and
            $provisionSteps.Count -eq 1 -and $provisionStep.Count -eq 1 -and [int]$provisionStep[0].decision.arguments.Amount -eq 1 -and $selectedFoodOffer.Count -eq 1 -and $cheapestFoodOffer.Count -eq 1 -and [string]$selectedFoodOffer[0].viewModelItemId -ceq [string]$cheapestFoodOffer[0].viewModelItemId -and [int]$provisionStep[0].actionReceipt.data.nativeTransactionAmount -le [double]$cheapestFoodOffer[0].inventoryLogicUnitPrice -and
            $tradeCommitSteps.Count -eq 1 -and $tradeCommit.Count -eq 1 -and [bool]$tradeCommit[0].actionReceipt.data.committed -and [bool]$tradeCommit[0].actionReceipt.data.postconditionPassed -and
            $waitEntrySteps.Count -eq 1 -and $waitEntry.Count -eq 1 -and $waitOption.Count -eq 1 -and [string]$waitEntry[0].observationBefore.state.context.menuId -eq 'town' -and
            $restSteps.Count -eq 1 -and [int]$restStep[0].decision.arguments.Days -eq 3 -and $hostRestMonitorSteps.Count -eq 1 -and [bool]$hostRestMonitor[0].control.requestedRestCompleted -and [int]$hostRestMonitor[0].control.pollCount -gt 0 -and
            $hostRestLeaveSteps.Count -eq 1 -and $hostRestLeaveOption.Count -eq 1 -and
            $leaveWaitSteps.Count -eq 1 -and $leaveWait.Count -eq 1 -and $leaveOption.Count -eq 1 -and [string]$leaveWait[0].observationBefore.state.context.menuId -eq 'town_wait_menus' -and
            $naturalTicksElapsed -eq 3 -and [double]$finalObservation.campaignDay -ge ([double]$supplySetup.CampaignDay + 3.0) -and
            [string]$finalObservation.state.context.menuId -eq 'town' -and [int]$finalObservation.state.party.members -eq 6 -and
            [int]$finalObservation.state.economy.gold -ge 861 -and [double]$finalObservation.state.party.food -ge 1.0 -and
            $nativeClockActions.Count -eq 0 -and $rejectedSteps.Count -le 2 -and $rejectedActionsDidNotChangeWorld -and $providerStoppedAfterGoalAction -and [bool]$loopTrace.termination.goalVerified
        )
        if ($finalObservation -and $finalObservation.state) {
            $supplyVerification = [ordered]@{
                Members = [int]$finalObservation.state.party.members
                Gold = [int]$finalObservation.state.economy.gold
                Food = [double]$finalObservation.state.party.food
                FoodInventory = [int]$finalObservation.state.party.foodInventory
                CampaignDayStart = [double]$supplySetup.CampaignDay
                CampaignDayEnd = [double]$finalObservation.campaignDay
                DailyTickStart = [int]$supplySetup.DailyTickCount
                DailyTickEnd = [int]$finalObservation.dailyTickCount
                DailyTicksElapsed = $naturalTicksElapsed
                HostRestPollCount = if ($hostRestMonitor.Count -eq 1) { [int]$hostRestMonitor[0].control.pollCount } else { 0 }
                HostRestTickSamples = if ($hostRestMonitor.Count -eq 1) { $hostRestMonitor[0].control.tickSamples } else { @() }
                HostWaitLeaveActionCompleted = ($hostRestLeaveSteps.Count -eq 1)
                ModelDecisionCount = [int]$loopTrace.decisions
                FoodItemId = if ($provisionStep.Count -eq 1) { [string]$provisionStep[0].actionReceipt.data.itemId } else { '' }
                FoodAmount = if ($provisionStep.Count -eq 1) { [int]$provisionStep[0].decision.arguments.Amount } else { 0 }
                FoodUnitPrice = if ($selectedFoodOffer.Count -eq 1) { [double]$selectedFoodOffer[0].inventoryLogicUnitPrice } else { 0.0 }
                NativeTransactionAmount = if ($provisionStep.Count -eq 1) { [int]$provisionStep[0].actionReceipt.data.nativeTransactionAmount } else { 0 }
                NativeRestDaysRequested = if ($restStep.Count -eq 1) { [int]$restStep[0].decision.arguments.Days } else { 0 }
                NativeRestRequestCount = $restSteps.Count
                NativeGoalVerified = [bool]$loopTrace.termination.goalVerified
                NativeClockActions = @($nativeClockActions | ForEach-Object { [string]$_.actionReceipt.action })
                RejectedDecisions = $rejectedSteps.Count
                RejectedActionsPreservedWorldState = $rejectedActionsDidNotChangeWorld
                Passed = [bool]$supplyVerified
            }
        }
        if (-not $supplyVerified) { throw 'Real model failed the frozen Native multi-day supply postconditions; preserve the captured trace and engine frame.' }
    }
    else {
    $targetQueries = @($steps | Where-Object { $_.decision.action -eq 'mapSettlementTargets' -and $_.actionReceipt.status -eq 'completed' })
    $moveSteps = @($steps | Where-Object { $_.decision.action -eq 'move' -and $_.actionReceipt.status -eq 'completed' })
    $finalMoveStep = @($moveSteps | Select-Object -Last 1)
    $allowedMoveCount = if ($RoadsideBanditNegotiationLoop) { 2 } else { 1 }
    if ($moveSteps.Count -lt 1 -or $moveSteps.Count -gt $allowedMoveCount -or ($RoadsideBanditNegotiationLoop -and $moveSteps.Count -ne 2)) {
        throw "Live model issued $($moveSteps.Count) successful Native moves; the selected goal permits $(if($RoadsideBanditNegotiationLoop){'exactly two after the interrupted target is cleared'}else{"at most $allowedMoveCount"})."
    }
    if ($targetQueries.Count -eq 0 -and -not $RecruitmentLoop) { throw 'This acceptance slice requires an on-demand mapSettlementTargets receipt before moving.' }
    $moveSafetyResults = foreach ($candidateMove in $moveSteps) {
        $moveTargetId = [string]$candidateMove.decision.arguments.SettlementId
        $currentTargets = @($candidateMove.observationBefore.state.nearbySettlements)
        $target = @($currentTargets | Where-Object { [string]$_.id -ceq $moveTargetId } | Select-Object -First 1)
        $currentId = [string]$candidateMove.observationBefore.state.location.currentSettlementId
        [bool]($target.Count -eq 1 -and [string]$target[0].id -cne $currentId -and [double]$target[0].distance -gt 1.0 -and -not [bool]$target[0].hostile -and -not [bool]$target[0].underSiege -and [string]$candidateMove.observationAfter.state.location.targetSettlementId -ceq $moveTargetId)
    }
    $chosenId = [string]$finalMoveStep[0].decision.arguments.SettlementId
    $observedTargets = @($finalMoveStep[0].observationBefore.state.nearbySettlements)
    $chosenTarget = @($observedTargets | Where-Object { [string]$_.id -ceq $chosenId } | Select-Object -First 1)
    $chosenObservedSafeTarget = ($chosenTarget.Count -eq 1 -and [string]$chosenTarget[0].id -cne [string]$finalMoveStep[0].observationBefore.state.location.currentSettlementId -and [double]$chosenTarget[0].distance -gt 1.0 -and -not [bool]$chosenTarget[0].hostile -and -not [bool]$chosenTarget[0].underSiege)
    $nativeMovementObserved = @($moveSafetyResults | Where-Object { -not $_ }).Count -eq 0
    $targetSource = if ($targetQueries.Count -gt 0) { 'current Native nearbySettlements observations; mapSettlementTargets queried on demand' } else { 'current native nearbySettlements observations' }
    $observeSteps = @($steps | Where-Object { $_.control.kind -eq 'bounded-observe-again' -and -not $_.actionExecuted -and $_.observationAfter.status -eq 'completed' })
    # A completed provider decision (for example, `done` after a verified arrival)
    # has no observationAfter. Use the latest actual Native observation in the trace,
    # not the initial baseline, when checking arrival and naturally elapsed Campaign time.
    $lastObservedStep = @($steps | Where-Object { $_.observationAfter -and $_.observationAfter.state } | Select-Object -Last 1)
    $finalObservation = if ($lastObservedStep.Count -gt 0) { $lastObservedStep[0].observationAfter } else { $baseline }
    $arrivalConfirmed = ([string]$finalObservation.state.location.currentSettlementId -ceq $chosenId)
    $campaignDayAdvancedDuringTravel = ([double]$finalObservation.campaignDay -gt [double]$finalMoveStep[0].actionReceipt.campaignDay)
    $expectedGoalActionCount = if ($RecruitmentLoop) { $null } else { 2 }
    $providerStoppedAfterGoalAction = ([bool]$loopTrace.termination.completedByProvider -and [bool]$steps[-1].decision.done -and ($null -eq $expectedGoalActionCount -or [int]$loopTrace.actionsExecuted -eq $expectedGoalActionCount))
    if (-not $chosenObservedSafeTarget -or -not $nativeMovementObserved) { throw 'Native move did not match a safe settlement id returned by the visible-target query.' }
    $preNativeTravelReobservations = @($steps | Where-Object {
        $_.control.kind -eq 'decision-rejected-before-native' -and
        $_.observationAfter.status -eq 'completed' -and
        [string]$_.observationAfter.state.location.currentSettlementId -ceq $chosenId -and
        [double]$_.observationAfter.campaignDay -gt [double]$finalMoveStep[0].actionReceipt.campaignDay
    })
    $nativeReadObservationsAfterMove = @($steps | Where-Object {
        [int]$_.iteration -gt [int]$finalMoveStep[0].iteration -and
        [double]$_.observationBefore.campaignDay -gt [double]$finalMoveStep[0].actionReceipt.campaignDay -and
        (
            ([bool]$_.observationBefore.state.party.isMoving -and [string]$_.observationBefore.state.location.targetSettlementId -ceq $chosenId -and [string]$_.observationBefore.state.context.timeControlMode -in @('StoppablePlay','UnstoppableFastForward')) -or
            ([string]$_.observationBefore.state.location.currentSettlementId -ceq $chosenId -and [string]$_.observationBefore.state.context.menuId -in @('town','town_backstreet','village'))
        )
    })
    $travelReobserved = ($observeSteps.Count -gt 0 -or $preNativeTravelReobservations.Count -gt 0 -or $nativeReadObservationsAfterMove.Count -gt 0)
    if (($ArrivalLoop -or $RecruitmentLoop) -and (-not $arrivalConfirmed -or -not $travelReobserved -or -not $campaignDayAdvancedDuringTravel)) {
        throw 'Live-model arrival slice lacked a verified target settlement, a fresh Native re-observation during travel, or natural Campaign-time advancement.'
    }
    if ($RecruitmentLoop) {
        $offerStep = @($steps | Where-Object { $_.decision.action -eq 'recruitOptions' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
        $recruitStep = @($steps | Where-Object { $_.decision.action -eq 'recruit' -and $_.actionReceipt.status -eq 'completed' } | Select-Object -First 1)
        if ($offerStep.Count -ne 1 -or $recruitStep.Count -ne 1) { throw 'Real model did not inspect one Native recruitment offer and submit one recruitment transaction.' }
        $recruitMenuOption = @($offerStep[0].observationBefore.state.availableMenuOptions | Where-Object { $_.id -eq 'recruit_volunteers' -and $_.available -and $_.enabled } | Select-Object -First 1)
        $offerReceipt = $offerStep[0].actionReceipt
        $chosenOffer = @($offerReceipt.data.offers | Where-Object { $_.available -and [string]$_.ownerId -ceq [string]$recruitStep[0].decision.arguments.OwnerId -and [string]$_.troopId -ceq [string]$recruitStep[0].decision.arguments.TroopId -and [int]$_.slot -eq [int]$recruitStep[0].decision.arguments.VolunteerSlot -and [int]$_.cost -le [int]$offerStep[0].observationBefore.state.economy.gold } | Select-Object -First 1)
        $recruitBefore = $recruitStep[0].observationBefore.state
        $recruitAfter = $recruitStep[0].observationAfter.state
        $nativeRecruitmentVerified = (
            $recruitMenuOption.Count -eq 1 -and
            $offerStep[0].observationBefore.state.location.currentSettlementId -ceq $chosenId -and
            $offerStep[0].observationBefore.state.context.menuId -in @('town','town_backstreet','village') -and
            $chosenOffer.Count -eq 1 -and
            -not [bool]$recruitStep[0].decision.arguments.ConfirmPartySizeWarning -and
            [bool]$recruitStep[0].actionReceipt.data.verified -and
            [int]$recruitAfter.party.members -eq ([int]$recruitBefore.party.members + 1) -and
            [int]$recruitBefore.economy.gold - [int]$recruitAfter.economy.gold -eq [int]$chosenOffer[0].cost
        )
        if (-not $nativeRecruitmentVerified) { throw 'Native volunteer recruitment did not match the current enabled menu option, observed offer, party-size delta, and Gold cost.' }
        $actionsAfterRecruitment = @($steps | Where-Object { $_.actionExecuted -and [int]$_.iteration -gt [int]$recruitStep[0].iteration })
        $expectedActionCount = if ($RoadsideBanditNegotiationLoop) { $null } else { 3 }
        $providerStoppedAfterGoalAction = ([bool]$loopTrace.termination.completedByProvider -and [bool]$steps[-1].decision.done -and $actionsAfterRecruitment.Count -eq 0 -and ($null -eq $expectedActionCount -or [int]$loopTrace.actionsExecuted -eq $expectedActionCount))
        if (-not $providerStoppedAfterGoalAction) { throw 'Live model did not stop after Native recruitment postconditions were observed.' }
    }
    elseif (-not $ArrivalLoop -and -not $providerStoppedAfterGoalAction) { throw 'Live model did not stop after the single requested Native move order.' }
    if ($ArrivalLoop -and -not $providerStoppedAfterGoalAction) { throw 'Live model did not stop after Native arrival was observed.' }
    }

    $null = Capture-EngineFrame 'LiveModelEngine-after'
    Write-LiveModelCaptureEvent 'capture-end' ([DateTime]::UtcNow.ToString('O')) 'capture' $null $finalObservation.state $null $capture
    $captureResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactSheetPath -EventTracePath $eventTracePath -KeepVideo
    $capture = $null

    $liveModelTrace = [ordered]@{
        ProviderKind = 'configured live model provider'
        ProviderProtocol = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_PROTOCOL)) { 'openai-compatible' } else { [string]$env:CHRONICLE_LLM_PROTOCOL }
        ModelId = [string]$env:CHRONICLE_LLM_MODEL
        ModelMaxOutputTokens = if ($loopTrace.providerBudget) { [int]$loopTrace.providerBudget.maxOutputTokensPerCall } else { [int]$env:CHRONICLE_LLM_MAX_TOKENS }
        ModelThinkingMode = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_THINKING_MODE)) { 'provider-default' } else { [string]$env:CHRONICLE_LLM_THINKING_MODE }
        ModelReasoningEffort = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_REASONING_EFFORT)) { 'provider-default' } else { [string]$env:CHRONICLE_LLM_REASONING_EFFORT }
        SourceCommit = $sourceCommit
        SourceTrackedTreeClean = $sourceTrackedTreeClean
        RunStartedUtc = $modelRunStartedUtc
        RunCompletedUtc = [DateTime]::UtcNow.ToString('O')
        CampaignDayStart = [double]$baseline.campaignDay
        CampaignDayEnd = [double]$finalObservation.campaignDay
        StartupDialogReceipts = @($start.session.startupDialogReceipts)
        Goal = $goal
        AcceptanceSlice = if ($SupplyManagementLoop) { 'Real-model Native food purchase and three-day Town Wait' } elseif ($RoadsideBanditNegotiationLoop) { 'Native roadside Safe Passage, recovery, and volunteer recruitment' } elseif ($RecruitmentLoop) { 'Native movement plus volunteer recruitment' } elseif ($ArrivalLoop) { 'Native movement arrival' } else { 'Native movement order accepted' }
        SafePassageRoute = $safePassageRoute
        HarnessWorldEvents = @($loopTrace.harnessEvents)
        ChosenSettlementId = $chosenId
        ChosenSettlementName = [string]$chosenTarget[0].name
        ObservedTargetCount = $observedTargets.Count
        QueryThenNativeMoveVerified = (-not $SupplyManagementLoop)
        ChosenTargetSource = $targetSource
        ArrivalConfirmed = $arrivalConfirmed
        BoundedReobservations = $observeSteps.Count
        NativeReadObservationsAfterMove = $nativeReadObservationsAfterMove.Count
        NativeTravelReobservations = ($observeSteps.Count + $preNativeTravelReobservations.Count)
        CampaignDayAdvancedDuringTravel = $campaignDayAdvancedDuringTravel
        RecruitmentVerified = if ($RecruitmentLoop) { [bool]$nativeRecruitmentVerified } else { $null }
        SupplyFixtureSetup = $supplySetup
        SupplyVerified = if ($SupplyManagementLoop) { [bool]$supplyVerified } else { $null }
        SupplyVerification = $supplyVerification
        SupplyNativeClockActions = if ($SupplyManagementLoop) { @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -in @('advance','pause','resume','fastForward') } | ForEach-Object { [string]$_.actionReceipt.action }) } else { @() }
        ProviderStoppedAfterGoalAction = $providerStoppedAfterGoalAction
        ProviderBudget = $loopTrace.providerBudget
        HostFailureStage = $loopTrace.failureStage
        HostFailureExceptionType = $loopTrace.failureExceptionType
        HostFailureDetail = $loopTrace.failureDetail
        HostFailureStack = $loopTrace.failureStack
        HostLastSelectedAction = $loopTrace.lastSelectedAction
        Decisions = [int]$loopTrace.decisions
        NativeActionReceipts = @($steps | Where-Object { $_.actionExecuted } | ForEach-Object { [ordered]@{ action = $_.actionReceipt.action; status = $_.actionReceipt.status; campaignDay = $_.actionReceipt.campaignDay; timing = $_.timing } })
        HarnessEvents = @($loopTrace.harnessEvents)
        Trace = $loopTrace.trace
        VisualEvidence = [ordered]@{
            Provider = $captureResult.Provider
            FrameCoverageRatio = $captureResult.FrameCoverageRatio
            DurationSeconds = $captureResult.DurationSeconds
            ContactSheetPath = $contactSheetPath
            TimelineIndexPath = $captureResult.TimelineIndexPath
            EventTracePath = $eventTracePath
            EngineFrameBeforePath = $engineFrameBeforePath
            EngineFrameAfterPath = $engineFrameAfterPath
            SourceVideoPath = $videoPath
            SourceVideoSha256 = $captureResult.SourceVideoSha256
        }
        FixtureHashBefore = $fixtureHashBefore
    }
}
catch {
    $failure = $_.Exception.Message
    # Preserve the decision/action trace even when a later acceptance assertion fails.
    # This is diagnostic evidence, not a pass result.
    if ($loopTrace -and -not $liveModelTrace) {
        $liveModelTrace = [ordered]@{
            ProviderKind = 'configured live model provider; failed before acceptance'
            ProviderProtocol = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_PROTOCOL)) { 'openai-compatible' } else { [string]$env:CHRONICLE_LLM_PROTOCOL }
            ModelId = [string]$env:CHRONICLE_LLM_MODEL
            ModelMaxOutputTokens = if ($loopTrace.providerBudget) { [int]$loopTrace.providerBudget.maxOutputTokensPerCall } else { [int]$env:CHRONICLE_LLM_MAX_TOKENS }
            ModelThinkingMode = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_THINKING_MODE)) { 'provider-default' } else { [string]$env:CHRONICLE_LLM_THINKING_MODE }
            ModelReasoningEffort = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_REASONING_EFFORT)) { 'provider-default' } else { [string]$env:CHRONICLE_LLM_REASONING_EFFORT }
            SourceCommit = $sourceCommit
            SourceTrackedTreeClean = $sourceTrackedTreeClean
            ProviderBudget = $loopTrace.providerBudget
            HostFailureStage = $loopTrace.failureStage
            HostFailureExceptionType = $loopTrace.failureExceptionType
            HostFailureDetail = $loopTrace.failureDetail
            HostFailureStack = $loopTrace.failureStack
            HostLastSelectedAction = $loopTrace.lastSelectedAction
            RunStartedUtc = $modelRunStartedUtc
            RunCompletedUtc = [DateTime]::UtcNow.ToString('O')
            CampaignDayStart = if ($baseline) { [double]$baseline.campaignDay } else { $null }
            CampaignDayEnd = if ($loopTrace.lastObservation) { [double]$loopTrace.lastObservation.campaignDay } else { $null }
            Goal = $goal
            AcceptanceSlice = if ($SupplyManagementLoop) { 'Real-model Native food purchase and three-day Town Wait' } else { 'Failed live-model decision loop' }
            SupplyFixtureSetup = $supplySetup
            SupplyVerified = $false
            SupplyVerification = if ($SupplyManagementLoop -and $loopTrace.lastObservation) {
                [ordered]@{
                    Members = [int]$loopTrace.lastObservation.state.party.members
                    Gold = [int]$loopTrace.lastObservation.state.economy.gold
                    Food = [double]$loopTrace.lastObservation.state.party.food
                    FoodInventory = [int]$loopTrace.lastObservation.state.party.foodInventory
                    CampaignDayStart = if ($supplySetup) { [double]$supplySetup.CampaignDay } else { $null }
                    CampaignDayEnd = [double]$loopTrace.lastObservation.campaignDay
                    DailyTickStart = if ($supplySetup) { [int]$supplySetup.DailyTickCount } else { $null }
                    DailyTickEnd = [int]$loopTrace.lastObservation.dailyTickCount
                    DailyTicksElapsed = if ($supplySetup) { [int]$loopTrace.lastObservation.dailyTickCount - [int]$supplySetup.DailyTickCount } else { 0 }
                    ModelDecisionCount = [int]$loopTrace.decisions
                    NativeActionCount = [int]$loopTrace.actionsExecuted
                    RejectedDecisions = @($loopTrace.trace | Where-Object { $_.control.kind -eq 'decision-rejected-before-native' -or ($_.actionAttempted -and [string]$_.actionReceipt.status -eq 'rejected') }).Count
                    RejectedActionsPreservedWorldState = $null
                    FailureStatus = [string]$loopTrace.status
                    Failure = [string]$loopTrace.error
                    Passed = $false
                }
            } else { $null }
            Trace = $loopTrace.trace
            Termination = $loopTrace.termination
            LastObservation = $loopTrace.lastObservation
            ActionsExecuted = $loopTrace.actionsExecuted
            DecisionCount = $loopTrace.decisions
            Decisions = $loopTrace.decisions
            HarnessEvents = @($loopTrace.harnessEvents)
            Failure = $failure
            VisualEvidence = $null
        }
    }
    if ($capture) {
        try {
            $failedState = if ($loopTrace -and $loopTrace.lastObservation -and $loopTrace.lastObservation.state) { $loopTrace.lastObservation.state } else { $baseline.state }
            $failedUtc = if ($loopTrace -and $loopTrace.timing -and $loopTrace.timing.providerCompletedUtc) { [string]$loopTrace.timing.providerCompletedUtc } else { [DateTime]::UtcNow.ToString('O') }
            Write-LiveModelCaptureEvent 'model-loop-failed' $failedUtc 'modelLoopFailure' $null $failedState $null $capture
        }
        catch { if (-not $failureEvidenceError) { $failureEvidenceError = "Could not align failure event: $($_.Exception.Message)" } }
    }
    if ($sessionStarted) {
        try { $null = Capture-EngineFrame 'LiveModelEngine-failure'; $failureEngineFrameCaptured = $true }
        catch { $failureEvidenceError = $_.Exception.Message }
    }
}
finally {
    if ($capture) {
        try {
            $captureResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactSheetPath -EventTracePath $eventTracePath -KeepVideo
        }
        catch {
            [ordered]@{ stoppedUtc = (Get-Date).ToUniversalTime().ToString('O'); error = $_.Exception.Message; videoPath = $videoPath; eventTracePath = $eventTracePath } |
                ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDirectory 'LiveModelWindow-partial.json') -Encoding UTF8
            try { if ($capture.Process -and -not $capture.Process.HasExited) { $capture.Process.Kill() } } catch { }
        }
        $capture = $null
    }
    if ($sessionStarted -or (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
        try { $stop = Invoke-AgentCli 'stop' } catch { if (-not $failure) { $failure = "Agent session cleanup failed: $($_.Exception.Message)" } }
    }
    if ($null -eq $priorHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $priorHarnessMode }
    if ($null -eq $priorModelTimeout) { Remove-Item Env:CHRONICLE_LLM_TIMEOUT_SECONDS -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_LLM_TIMEOUT_SECONDS = $priorModelTimeout }
    if ($null -eq $priorModelMaxTokens) { Remove-Item Env:CHRONICLE_LLM_MAX_TOKENS -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_LLM_MAX_TOKENS = $priorModelMaxTokens }
}

$fixtureHashAfter = if (Test-Path -LiteralPath $savePath -PathType Leaf) { (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash } else { $null }
$fixtureUnchanged = ($fixtureHashBefore -ceq $fixtureHashAfter)
$processStopped = ([bool]$stop.processStopped -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf) -and -not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue))
$capturePassed = ($captureResult -and $captureResult.Passed -and [double]$captureResult.FrameCoverageRatio -ge 0.9 -and $captureResult.WindowTitle -match 'Bannerlord')
$passed = (-not $failure -and $null -ne $liveModelTrace -and $fixtureUnchanged -and $processStopped -and $capturePassed)

if ($passed -and (Test-Path -LiteralPath $videoPath -PathType Leaf)) {
    Remove-Item -LiteralPath $videoPath -Force
    if (Test-Path -LiteralPath $timelineIndexPath -PathType Leaf) {
        $timelineIndex = Get-Content -LiteralPath $timelineIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $timelineIndex.sourceClip.retained = $false
        $timelineIndex.sourceClip.removedAfterEvidence = $true
        $timelineIndex | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $timelineIndexPath -Encoding UTF8
    }
    if ($liveModelTrace.VisualEvidence) { $liveModelTrace.VisualEvidence.SourceVideoPath = $null; $liveModelTrace.VisualEvidence.SourceVideoRemovedAfterKeyframes = $true }
    if ($captureResult) { $captureResult.VideoRetained = $false; $captureResult.VideoRemovedAfterEvidence = $true }
}

$result = [ordered]@{
    ProviderKind = 'configured OpenAI-compatible live model; not a stub'
    Passed = $passed
    Failure = $failure
    FixtureUnchanged = $fixtureUnchanged
    ProcessStopped = $processStopped
    VisualEvidencePassed = [bool]$capturePassed
    FailureEngineFrameCaptured = $failureEngineFrameCaptured
    FailureEvidenceError = $failureEvidenceError
    FailureEngineFramePath = if ($failureEngineFrameCaptured) { $engineFrameFailurePath } else { $null }
    ProcessId = if ($start -and $start.session) { $start.session.processId } else { $null }
    Capture = $captureResult
    Trace = $liveModelTrace
}
$json = $result | ConvertTo-Json -Depth 28
if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
    Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'LiveModelLoopResult.json') -Value $json -Encoding UTF8
}
$json
if (-not $passed) { exit 1 }
