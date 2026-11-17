[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [string]$CheckpointSaveName,
    [ValidateRange(1,160)][int]$MaxProviderDecisions = 160,
    [int]$TimeoutSeconds = 180,
    [ValidateRange(60,86400)][int]$HostMaxElapsedSeconds = 86400,
    [ValidateRange(5,30)][int]$FrameRate = 10,
    [switch]$ArrivalLoop,
    [switch]$RecruitmentLoop,
    [switch]$RoadsideBanditNegotiationLoop,
    [switch]$SupplyManagementLoop,
    [switch]$VillageToolsQuestLoop,
    [switch]$BattleSimulationLoop,
    [switch]$BattleAndCaptivityLoop,
    [switch]$CaptivityRecoveryLoop,
    [switch]$EstablishYourClanGoalPlanner,
    [switch]$EstablishYourClanAutonomyLoop,
    [switch]$EstablishClanGoldSaleLoop,
    [switch]$AgentHostRuntime
)

$ErrorActionPreference = 'Stop'
$freeLlmProfileHelper = Join-Path $PSScriptRoot 'Get-FreeLLMAPIProfile.ps1'
. $freeLlmProfileHelper
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$loop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Agent-OpenAICompatibleProvider.ps1'
$videoLibrary = Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1'
$documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documentsPath)) { throw 'Windows Documents directory could not be resolved for the live-model fixture.' }
$documentsRoot = Join-Path $documentsPath 'Mount and Blade II Bannerlord'
$savePath = Join-Path $documentsRoot "Game Saves\$LoadSaveName.sav"
$checkpointSavePath = if (-not [string]::IsNullOrWhiteSpace($CheckpointSaveName)) { Join-Path $documentsRoot "Game Saves\$CheckpointSaveName.sav" } else { $null }
$sessionPath = Join-Path $documentsRoot 'AgentRuns\ChronicleAgent\session.json'
$diagnosticLog = Join-Path $documentsRoot 'Configs\ModLogs\chronicle-framework.log'

function Get-NativeCheckpointStateDisposition([object]$StateReceipt) {
    if ($null -eq $StateReceipt -or [string]$StateReceipt.status -cne 'completed' -or $null -eq $StateReceipt.state) { return $null }
    $state = $StateReceipt.state
    $context = $state.context
    if ([string]$context.gameState -cne 'MapState' -or [bool]$context.escapeMenuOpen -or [bool]$context.inquiryOpen -or
        $null -ne $context.battleSimulation -or $null -ne $context.conversation -or
        ($null -ne $context.lootItemCount -and [int]$context.lootItemCount -gt 0) -or
        [bool]$state.partyScreenOpen -or [bool]$state.inventoryScreenOpen -or
        [bool]$context.captivity.isCaptive) { return $null }

    $menuId = [string]$context.menuId
    if ([string]::IsNullOrWhiteSpace($menuId) -and -not [bool]$context.encounterActive -and
        [string]::IsNullOrWhiteSpace([string]$context.encounteredPartyId)) { return 'native-campaign-map' }

    $currentSettlementId = [string]$state.location.currentSettlementId
    if ([string]::IsNullOrWhiteSpace($currentSettlementId) -or
        ([bool]$context.encounterActive -and [string]$context.encounteredPartyId -cne $currentSettlementId)) { return $null }
    $isBackstreet = $menuId -ceq 'town_backstreet'
    $isStandardSettlementMenu = $menuId -in @('town','village','castle')
    if (-not $isBackstreet -and -not $isStandardSettlementMenu) { return $null }
    if ($isBackstreet -and @($state.availableMenuOptions | Where-Object {
        [string]$_.id -ceq 'town_backstreet_back' -and [bool]$_.available -and [bool]$_.enabled -and [bool]$_.isLeave
    }).Count -ne 1) { return $null }

    $currentSettlement = @($state.nearbySettlements | Where-Object { [string]$_.id -ceq $currentSettlementId } | Select-Object -First 1)
    if ($currentSettlement.Count -ne 1 -or [string]$currentSettlement[0].type -notin @('town','village','castle') -or [bool]$currentSettlement[0].underSiege)
        { return $null }
    return 'native-settlement-menu'
}

function Test-NativeCheckpointStateContract {
    $safeBackstreet = [pscustomobject]@{
        status = 'completed'
        state = [pscustomobject]@{
            context = [pscustomobject]@{
                gameState='MapState'; menuId='town_backstreet'; encounterActive=$true; encounteredPartyId='town_ES3';
                escapeMenuOpen=$false; inquiryOpen=$false; battleSimulation=$null; captivity=[pscustomobject]@{ isCaptive=$false }
            }
            location=[pscustomobject]@{ currentSettlementId='town_ES3' }
            partyScreenOpen=$false; inventoryScreenOpen=$false
            availableMenuOptions=@([pscustomobject]@{ id='town_backstreet_back'; available=$true; enabled=$true; isLeave=$true })
            nearbySettlements=@([pscustomobject]@{ id='town_ES3'; type='town'; underSiege=$false })
        }
    }
    if ((Get-NativeCheckpointStateDisposition $safeBackstreet) -cne 'native-settlement-menu') {
        throw 'Native Town Backstreet with a current enabled Back option, matching town encounter and non-sieged settlement must be checkpointable.'
    }
    $unsafeBackstreet = $safeBackstreet | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $unsafeBackstreet.state.availableMenuOptions[0].enabled = $false
    if ($null -ne (Get-NativeCheckpointStateDisposition $unsafeBackstreet)) {
        throw 'A Town Backstreet checkpoint must be rejected when the current Native Back/Leave action is unavailable.'
    }
    $unsafeMission = $safeBackstreet | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $unsafeMission.state.context.gameState = 'MissionState'
    if ($null -ne (Get-NativeCheckpointStateDisposition $unsafeMission)) {
        throw 'A Tavern Mission cannot be treated as a safe Campaign checkpoint merely because its settlement is valid.'
    }
    $unsafeSiege = $safeBackstreet | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $unsafeSiege.state.nearbySettlements[0].underSiege = $true
    if ($null -ne (Get-NativeCheckpointStateDisposition $unsafeSiege)) {
        throw 'A settlement Backstreet under siege cannot be treated as a safe persistent checkpoint.'
    }
    return [pscustomobject]@{ passed=$true; safeBackstreet='native-settlement-menu'; unavailableLeaveRejected=$true; missionStateRejected=$true; siegeRejected=$true }
}

$checkpointStateContract = Test-NativeCheckpointStateContract

if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) {
    throw 'Refusing to start a live-model Campaign test while any Bannerlord client is already running.'
}
if ($CheckpointSaveName) {
    if (-not $EstablishYourClanAutonomyLoop -or -not $AgentHostRuntime) { throw 'CheckpointSaveName is only supported for the Native AgentHost EYC development campaign.' }
    if ($CheckpointSaveName -notmatch '^[A-Za-z0-9_-]{1,48}$' -or $CheckpointSaveName -ceq $LoadSaveName) { throw 'A Native EYC checkpoint requires a unique 1-48 character save name distinct from its source.' }
    if (Test-Path -LiteralPath $checkpointSavePath) { throw 'The Native EYC checkpoint name already exists; refusing to overwrite it.' }
}
if (@($ArrivalLoop, $RecruitmentLoop, $RoadsideBanditNegotiationLoop, $SupplyManagementLoop, $VillageToolsQuestLoop, $BattleSimulationLoop, $BattleAndCaptivityLoop, $CaptivityRecoveryLoop, $EstablishYourClanGoalPlanner, $EstablishYourClanAutonomyLoop, $EstablishClanGoldSaleLoop | Where-Object { $_ }).Count -gt 1) { throw 'Select only one LiveModel test goal per run.' }
if ($AgentHostRuntime -and -not ($SupplyManagementLoop -or $ArrivalLoop -or $VillageToolsQuestLoop -or $BattleSimulationLoop -or $BattleAndCaptivityLoop -or $CaptivityRecoveryLoop -or $EstablishYourClanGoalPlanner -or $EstablishYourClanAutonomyLoop -or $EstablishClanGoldSaleLoop)) { throw 'AgentHostRuntime supports only frozen Native supply, arrival, supported Quest, battle/captivity, StoryMode planner/autonomy/recovery, and Gold-sale slices.' }
if ($VillageToolsQuestLoop -and -not $AgentHostRuntime) { throw 'VillageToolsQuestLoop requires the in-game .NET Agent Host route; the older PowerShell decision loop is not product evidence.' }
if ($EstablishYourClanGoalPlanner -and -not $AgentHostRuntime) { throw 'EstablishYourClanGoalPlanner requires the in-game .NET Agent Host route; the older PowerShell decision loop is not product evidence.' }
if ($EstablishYourClanAutonomyLoop -and -not $AgentHostRuntime) { throw 'EstablishYourClanAutonomyLoop requires the in-game .NET Agent Host route; the older PowerShell decision loop is not product evidence.' }
if ($EstablishClanGoldSaleLoop -and -not $AgentHostRuntime) { throw 'EstablishClanGoldSaleLoop requires the in-game .NET Agent Host route; the older PowerShell decision loop is not product evidence.' }
if ($RoadsideBanditNegotiationLoop -and -not $RecruitmentLoop) { throw 'RoadsideBanditNegotiationLoop requires RecruitmentLoop so the encounter resolves into the existing growth goal.' }
foreach ($setting in @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL','CHRONICLE_LLM_OUTPUT_MODE','CHRONICLE_LLM_MAX_RUN_COST_CNY','CHRONICLE_LLM_TIMEOUT_SECONDS','CHRONICLE_LLM_MAX_TOKENS','CHRONICLE_LLM_MAX_TOKEN_PARAMETER','CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION','CHRONICLE_LLM_REASONING_EFFORT','CHRONICLE_LLM_THINKING_MODE','CHRONICLE_LLM_TEMPERATURE','CHRONICLE_LLM_PROTOCOL')) {
    $configuredValue = [string][Environment]::GetEnvironmentVariable($setting, 'Process')
    if ([string]::IsNullOrWhiteSpace($configuredValue)) {
        $configuredValue = [string][Environment]::GetEnvironmentVariable($setting, 'User')
        if (-not [string]::IsNullOrWhiteSpace($configuredValue)) { [Environment]::SetEnvironmentVariable($setting, $configuredValue, 'Process') }
    }
    if ($setting -in @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL') -and [string]::IsNullOrWhiteSpace($configuredValue)) {
        throw "Live-model verification requires local $setting configuration; the value is never printed by this test."
    }
}
function Resolve-LiveModelProviderTimeout([AllowNull()][string]$ConfiguredValue, [ValidateRange(5,360)][int]$ScenarioDefaultSeconds) {
    if ([string]::IsNullOrWhiteSpace($ConfiguredValue)) { return $ScenarioDefaultSeconds }
    $requestedTimeoutSeconds = 0
    if (-not [int]::TryParse($ConfiguredValue, [ref]$requestedTimeoutSeconds) -or $requestedTimeoutSeconds -lt 5 -or $requestedTimeoutSeconds -gt 360) {
        throw 'CHRONICLE_LLM_TIMEOUT_SECONDS must be an integer from 5 to 360; no game process was started.'
    }
    return $requestedTimeoutSeconds
}
$timeoutOverrideContract = @(
    @{ Configured='90'; Default=360; Expected=90 },
    @{ Configured=''; Default=180; Expected=180 },
    @{ Configured='5'; Default=360; Expected=5 },
    @{ Configured='360'; Default=90; Expected=360 }
)
foreach ($case in $timeoutOverrideContract) {
    if ((Resolve-LiveModelProviderTimeout $case.Configured $case.Default) -ne $case.Expected) {
        throw 'Live-model provider timeout override/default contract failed before game launch.'
    }
}
function Set-LiveModelProviderTimeout([ValidateRange(5,360)][int]$ScenarioDefaultSeconds) {
    $env:CHRONICLE_LLM_TIMEOUT_SECONDS = [string](Resolve-LiveModelProviderTimeout ([string]$env:CHRONICLE_LLM_TIMEOUT_SECONDS) $ScenarioDefaultSeconds)
}
$configuredProtocol = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_PROTOCOL)) { 'openai-compatible' } else { [string]$env:CHRONICLE_LLM_PROTOCOL }
$providerEndpoint = $null
if ($configuredProtocol -cne 'openai-compatible' -or
    -not [Uri]::TryCreate([string]$env:CHRONICLE_LLM_BASE_URL, [UriKind]::Absolute, [ref]$providerEndpoint) -or
    $providerEndpoint.Scheme -notin @('http','https') -or ($providerEndpoint.Scheme -eq 'http' -and -not $providerEndpoint.IsLoopback) -or
    -not [string]::IsNullOrWhiteSpace($providerEndpoint.UserInfo) -or -not [string]::IsNullOrWhiteSpace($providerEndpoint.Query) -or
    -not [string]::IsNullOrWhiteSpace($providerEndpoint.Fragment)) {
    throw 'This live Campaign stage requires a configured OpenAI-compatible HTTPS provider (HTTP only on loopback); unsupported inference protocols are refused before Campaign launch.'
}
$isFreeLlmApi = $providerEndpoint.IsLoopback -and $providerEndpoint.Port -eq 31415 -and $providerEndpoint.AbsolutePath.TrimEnd('/') -eq '/v1'
$providerCredential = Get-ChronicleProviderCredential -Endpoint $providerEndpoint
$providerApiKey = [string]$providerCredential.Value
if (-not $providerEndpoint.IsLoopback -and [string]::IsNullOrWhiteSpace($providerApiKey)) {
    throw 'The configured remote OpenAI-compatible provider requires an environment API key; no key is printed or written to the model profile.'
}
$modelsUri = [UriBuilder]::new($providerEndpoint)
$modelsUri.Path = $providerEndpoint.AbsolutePath.TrimEnd('/') + '/models'
$modelsUri.Query = if ($isFreeLlmApi) { 'available=true' } else { '' }
try {
    $providerHeaders = if ([string]::IsNullOrWhiteSpace($providerApiKey)) { @{} } else { @{ Authorization = "Bearer $providerApiKey" } }
    $availableModelsResponse = Invoke-RestMethod -Uri $modelsUri.Uri -Method Get -Headers $providerHeaders -TimeoutSec 8
}
catch {
    $providerApiKey = $null
    $providerHeaders = $null
    throw 'The configured provider model-list preflight failed before Campaign launch; no inference request was sent and no fixture was started.'
}
finally {
    $providerApiKey = $null
    $providerHeaders = $null
}
if ($null -eq $availableModelsResponse -or $null -eq $availableModelsResponse.data) {
    throw 'The configured provider model-list response did not contain a data list; no inference request was sent and no fixture was started.'
}
if ($isFreeLlmApi) {
    $modelExecutionStatus = Get-FreeLLMAPIModelExecutionStatus -ModelRows @($availableModelsResponse.data) -ModelId ([string]$env:CHRONICLE_LLM_MODEL)
    if ($modelExecutionStatus -eq 'not-listed') {
        throw 'The configured model/route is not listed by FreeLLMAPI as currently available; no inference request was sent and no fixture was started.'
    }
    if ($modelExecutionStatus -notin @('ready', 'router')) {
        throw "The configured FreeLLMAPI route is not executable now (execution_status=$modelExecutionStatus); no inference request was sent and no fixture was started. Wait for provider recovery or select another ready route."
    }
}
elseif (@($availableModelsResponse.data | ForEach-Object { [string]$_.id }) -notcontains [string]$env:CHRONICLE_LLM_MODEL) {
    throw 'The configured model identifier is not listed by the configured provider; no inference request was sent and no fixture was started.'
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
$campaignInstanceId = $null
$priorHarnessMode = $env:CHRONICLE_HARNESS_MODE
$priorHarnessAgentInputLock = $env:CHRONICLE_HARNESS_AGENT_INPUT_LOCK
$harnessInputLockRequired = $false
$harnessInputLockConfirmed = $false
$priorModelTimeout = $env:CHRONICLE_LLM_TIMEOUT_SECONDS
$priorModelMaxTokens = $env:CHRONICLE_LLM_MAX_TOKENS
$priorModelMaxHttpRequests = $env:CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION
$sessionStarted = $false
$checkpointSaveOwned = $false
$checkpointSaveCompleted = $false
$checkpointSaveHash = $null
$checkpointSaveFailure = $null
$checkpointSaveStateDisposition = $null
$capture = $null
$captureResult = $null
$captureRecoveryProof = $null
$agentHostCaptureDecisionCount = 0
$agentHostCaptureEventsWritten = $false
$loopTrace = $null
$hostReadyMessages = @()
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
$battleTargetPreflight = $null
$goldSaleBaseline = $null
$goldSaleVerification = $null
$goldSaleVerified = $false
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
    $captureRecoveryProof = Test-ChronicleFragmentedCaptureResilience -EvidencePath (Join-Path $runDirectory 'FragmentedCaptureRecovery.json')
    Set-Content -LiteralPath $eventTracePath -Value '' -Encoding UTF8
    $env:CHRONICLE_HARNESS_MODE = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { 'visual-battle-fixture' } else { 'visual-capture' }
    $env:CHRONICLE_HARNESS_AGENT_INPUT_LOCK = '1'
    $harnessInputLockRequired = $true
    $env:CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION = '1'
    $loadArguments = @('-SaveName', $LoadSaveName)
    if ($EstablishYourClanGoalPlanner -or $EstablishYourClanAutonomyLoop -or $CaptivityRecoveryLoop -or $EstablishClanGoldSaleLoop) { $loadArguments += '-IncludeChronicleFramework' }
    $start = Invoke-AgentCli 'load' $loadArguments
    $sessionStarted = $true
    $baseline = Invoke-AgentCli 'state'
    if ($baseline.status -ne 'completed' -or $baseline.state.context.gameState -ne 'MapState') {
        throw 'Live-model fixture must load into Native Campaign Map state.'
    }
    $inputLockPattern = 'pid=' + [regex]::Escape([string]$start.session.processId) + '\|harness-agent-input-lock\|locked=True\|scope=' + [regex]::Escape([string]$env:CHRONICLE_HARNESS_MODE)
    $inputLockDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $inputLockDeadline) {
        if (Test-Path -LiteralPath $diagnosticLog -PathType Leaf) {
            $inputLockLines = @(Get-Content -LiteralPath $diagnosticLog -Tail 256 -Encoding UTF8 | Where-Object { $_ -match $inputLockPattern })
            if ($inputLockLines.Count -gt 0) { $harnessInputLockConfirmed = $true; break }
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $harnessInputLockConfirmed) {
        throw 'Harness game input lock was not confirmed on the test-owned process; no model request or gameplay action was sent.'
    }
    if ($EstablishYourClanAutonomyLoop) {
        $campaignIdentity = Invoke-AgentCli 'agentCheckpointGet'
        if ($campaignIdentity.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$campaignIdentity.data.campaignInstanceId)) {
            throw 'StoryMode continuation requires a verified Native campaign-instance identity before model inference.'
        }
        $campaignInstanceId = [string]$campaignIdentity.data.campaignInstanceId
    }
    if ($VillageToolsQuestLoop) {
        $visibleToolsMarker = @($baseline.state.settlementOverlayCharacters | Where-Object {
            @($_.questMarkers | Where-Object {
                [string]$_.type -eq 'AvailableIssue' -and
                (([string]$_.title + ' ' + [string]$_.hint) -match '(?i)tools?' -or (([string]$_.title + ' ' + [string]$_.hint).Contains(([char]0x5DE5).ToString() + ([char]0x5177).ToString())))
            }).Count -gt 0
        })
        if ([string]$baseline.state.context.menuId -ne 'village' -or [string]::IsNullOrWhiteSpace([string]$baseline.state.location.currentSettlementId) -or $visibleToolsMarker.Count -eq 0) {
            throw 'VillageToolsQuestLoop requires a disposable save loaded at a village menu with the current Native blue tools-issue marker visible; no model action was sent.'
        }
    }
    elseif ($EstablishYourClanGoalPlanner -or $EstablishYourClanAutonomyLoop) {
        $activeStoryClanQuest = @($baseline.state.quests | Where-Object { [string]$_.id -ceq 'rebuild_player_clan_storymode_quest' })
        if ($activeStoryClanQuest.Count -ne 1) { throw 'StoryMode objective testing requires the exact Establish Your Clan Quest to be active in the fresh Native state; no model decision was sent.' }
        if ([string]$baseline.state.storyModeEstablishClanStatus.status -cne 'active') { throw 'The Native StoryMode quest lifecycle observation did not classify the exact active Establish Your Clan Quest; no model decision was sent.' }
        if ($EstablishYourClanGoalPlanner -and [string]$baseline.state.context.timeControlMode -cne 'Stop') { throw 'Read-only planner fixture must already have the Native campaign clock stopped; the test will not change time mode.' }
    }
    elseif ($EstablishClanGoldSaleLoop) {
        $activeStoryClanQuest = @($baseline.state.quests | Where-Object { [string]$_.id -ceq 'rebuild_player_clan_storymode_quest' })
        if ($activeStoryClanQuest.Count -ne 1 -or [string]$baseline.state.storyModeEstablishClanStatus.status -cne 'active') { throw 'Gold sale requires the exact active original StoryMode Quest; no model decision was sent.' }
        $goldQuestReceipt = Invoke-AgentCli 'questDetails' @('-QuestId', 'rebuild_player_clan_storymode_quest', '-CommandId', ('gold-sale-journal-preflight-' + [Guid]::NewGuid().ToString('N')))
        if ($goldQuestReceipt.status -ne 'completed' -or [string]$goldQuestReceipt.data.questId -cne 'rebuild_player_clan_storymode_quest') { throw 'Native Journal preflight could not read the current original Gold objective; no model decision was sent.' }
        $goldTaskStages = @($goldQuestReceipt.data.journalStages | Where-Object { $_.hasTask })
        if ($goldTaskStages.Count -ne 4) { throw 'Native Establish Your Clan Journal must expose all four current objective stages; no model decision was sent.' }
        $goldLog = $goldTaskStages[0]
        if ([double]$goldLog.currentProgress -ge [double]$goldLog.targetProgress) { throw 'The official Journal Gold objective is already met; no sale or model call was sent.' }
        $goldSaleBaseline = [ordered]@{
            QuestId = [string]$goldQuestReceipt.data.questId
            JournalGoldCurrent = [double]$goldLog.currentProgress
            JournalGoldTarget = [double]$goldLog.targetProgress
            LiveGold = [int]$baseline.state.economy.gold
            PartyMembers = [int]$baseline.state.party.members
            CaptiveAtStart = [bool]$baseline.state.context.captivity.isCaptive
            CampaignDay = [double]$baseline.campaignDay
            TimeControlMode = [string]$baseline.state.context.timeControlMode
        }
    }
    elseif ($CaptivityRecoveryLoop) {
        $activeStoryClanQuest = @($baseline.state.quests | Where-Object { [string]$_.id -ceq 'rebuild_player_clan_storymode_quest' })
        if ($activeStoryClanQuest.Count -ne 1 -or [string]$baseline.state.storyModeEstablishClanStatus.status -cne 'active') { throw 'Existing-captivity recovery requires the exact active original StoryMode Quest; no model decision was sent.' }
        if ($baseline.state.context.captivity.isCaptive -ne $true -or [string]$baseline.state.context.menuId -cne 'prisoner_wait') { throw 'Existing-captivity recovery fixture must start at Native prisoner_wait with MainHero captive; no model decision was sent.' }
        if ([string]$baseline.state.context.timeControlMode -cne 'Stop' -or $baseline.state.context.isWaitMenu -ne $true -or $baseline.state.context.isWaitActive -ne $true -or @($baseline.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled }).Count -ne 0) { throw 'Existing-captivity recovery fixture must start stopped with a no-option active Native Wait menu; no model decision was sent.' }
    }
    elseif ($baseline.state.location.currentSettlementId) {
        throw 'Non-quest live-model map fixtures must remain unobstructed with no current settlement.'
    }
    if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) {
        $partyProbe = Invoke-AgentCli 'mapPartyTargets' @('-CommandId', ('battle-target-preflight-' + [Guid]::NewGuid().ToString('N')))
        if ($partyProbe.status -ne 'completed') { throw 'Native mapPartyTargets preflight failed; no model call was started.' }
        $visibleBandits = @($partyProbe.data.mapPartyTargets | Where-Object { $_.type -eq 'bandit' -and $_.hostile -eq $true })
        $battleTargetPreflight = [ordered]@{
            IsReadOnlyHarnessGate = $true
            ModelInferenceStarted = $false
            CampaignDay = [double]$baseline.campaignDay
            TimeControlMode = [string]$baseline.timeControlMode
            VisiblePartyCount = @($partyProbe.data.mapPartyTargets).Count
            VisibleHostileBanditCount = $visibleBandits.Count
            TargetAvailable = ($visibleBandits.Count -gt 0)
            TargetNames = @($visibleBandits | Select-Object -First 12 -ExpandProperty name)
        }
        $battleTargetPreflight | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'BattleTargetPreflight.json') -Encoding UTF8
        if ($visibleBandits.Count -eq 0) { throw 'No current Native-visible hostile Bandit was available in the selected world; the test stopped before model inference and did not create an encounter.' }
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
        Set-LiveModelProviderTimeout 180
        $env:CHRONICLE_LLM_MAX_TOKENS = '768'
    }
    elseif ($RecruitmentLoop) {
        $goal = 'Autonomously recruit one affordable local volunteer. Choose one safe target from current Native nearbySettlements observation; query mapSettlementTargets only if the current observation does not provide enough target information. The target must not be the current settlement, hostile, or under siege. Issue one move only. While still moving, use observeAgain with waitSeconds 5; never send move again or change clock controls. Once a fresh Native observation shows arrival, inspect the current settlement menu. If recruit_volunteers is currently available, call recruitOptions. Select one currently available offer that is affordable and fits party capacity; call recruit with its observed ownerId, troopId and slot, and ConfirmPartySizeWarning=false. After the Native receipt and fresh state show members increased by one and gold decreased by that offer cost, return done. If the current settlement has no eligible offer, use only newly observed safe settlement targets to replan; never invent inventory or force an over-capacity choice.'
        $maxDecisions = 24
        $maxElapsedSeconds = 600
        $allowedActions = 'mapSettlementTargets,move,recruitOptions,recruit'
        Set-LiveModelProviderTimeout 180
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
        Set-LiveModelProviderTimeout 180
        $env:CHRONICLE_LLM_MAX_TOKENS = '256'
    }
    elseif ($VillageToolsQuestLoop) {
        $goal = '完成当前可见的村庄工具委托'
        $maxDecisions = 160
        $maxElapsedSeconds = 7200
        $allowedActions = 'mapSettlementTargets,move,menuSelect,talkToSettlementHero,dialogueSelect,dialogueContinue,questDetails,tradeOptions,trade,tradeConfirm,tradeCancel,tradeCancelChanges,barterOptions,barterAutoBalance,barterOffer,barterCancel,inventoryOpen,heroEquipmentOptions,inventoryCancel'
        Set-LiveModelProviderTimeout 360
        $env:CHRONICLE_LLM_MAX_TOKENS = '1024'
    }
    elseif ($BattleSimulationLoop) {
        $goal = 'Resolve exactly one currently Native-visible hostile Bandit party encounter using the original Campaign map Send Troops/BattleSimulation. Pursue only a current visible mapPartyTargets candidate with hostile=true and type=bandit. If the Native bandit meeting shows its current Fight option, choose that Fight option, not toll or surrender. Use only Native BattleSimulation, then process current PartyState/InventoryState aftermath and return to Map. Verify actual pre/post party, gold, influence and renown; renown may be unchanged. Never control the clock or enter a real-time Mission.'
        $maxDecisions = 80
        $maxElapsedSeconds = 1800
        $allowedActions = 'mapPartyTargets,pursue,dialogueSelect,dialogueContinue,menuSelect,battleSkip,battleFinish,partyTakeAll,partyScreenDone,inventoryTakeAll,inventoryDone'
        Set-LiveModelProviderTimeout 360
        $env:CHRONICLE_LLM_MAX_TOKENS = '768'
    }
    elseif ($BattleAndCaptivityLoop) {
        $goal = 'Resolve one currently Native-visible hostile Bandit party via original Campaign Send Troops/BattleSimulation, then if the Native result captures MainHero continue through current Captivity until the Hero is free on Campaign Map. For any displayed ransom amount, use the current Native offer, current Gold and Campaign goal; choose only an enabled Native option. Do not use explicit clock actions, direct captivity APIs, or enter a real-time Mission.'
        $maxDecisions = 160
        $maxElapsedSeconds = 7200
        $allowedActions = 'mapPartyTargets,pursue,dialogueSelect,dialogueContinue,menuSelect,battleSkip,battleFinish,partyTakeAll,partyScreenDone,inventoryTakeAll,inventoryDone'
        Set-LiveModelProviderTimeout 360
        $env:CHRONICLE_LLM_MAX_TOKENS = '1024'
    }
    elseif ($CaptivityRecoveryLoop) {
        $goal = 'Recover this already captive MainHero from the current Native Captivity state, then re-read the still-active original Establish Your Clan quest and select one unmet objective. Do not start a battle or claim the quest complete. If the no-option wait menu is stopped and Native marks it wait-active, choose explicit Play as a separate Native action; while time flows, let the Host passively observe. At a current ransom menu, weigh its displayed price and current Gold against the goal and choose only an enabled Native accept/reject option. On a current allowlisted Native Captivity continuation page, choose only the currently enabled Continue option; re-observe because some pages return to captive waiting. Do not hardcode a threshold or write game state.'
        $maxDecisions = 120
        $maxElapsedSeconds = 7200
        $allowedActions = 'resume,menuSelect'
        Set-LiveModelProviderTimeout 360
        $env:CHRONICLE_LLM_MAX_TOKENS = '2048'
    }
    elseif ($EstablishClanGoldSaleLoop) {
        $goal = 'Make exactly one positive Native sale from the current PlayerInventory to increase the active original Establish Your Clan Gold Journal objective. If already captive at the start, first recover only through the current native captivity options; after reaching a usable free Map, move only to a fresh visible safe Town, enter its current Trade option, inspect current sell offers, sell exactly one transferable Goods unit and commit the Native draft. Read the active Quest Journal again and verify the Gold current progress increased. Do not buy, start a battle, alter resources directly, or claim the whole quest complete.'
        $maxDecisions = 160
        $maxElapsedSeconds = 7200
        $allowedActions = 'mapSettlementTargets,move,menuSelect,tradeOptions,trade,tradeConfirm,tradeCancel,tradeCancelChanges'
        Set-LiveModelProviderTimeout 360
        $env:CHRONICLE_LLM_MAX_TOKENS = '2048'
    }
    elseif ($EstablishYourClanAutonomyLoop) {
        $goal = 'Autonomously complete the exact currently active original StoryMode Establish Your Clan quest. Use its current Journal values to choose among Gold, dynamic PartySize, Renown and Companion targets; execute only the current Native routes, re-read Journal after each subgoal, and stop only after Native original quest history confirms completion. Do not inject progress, use preplanned action sequences, or hide time changes inside actions.'
        $maxDecisions = $MaxProviderDecisions
        $maxElapsedSeconds = $HostMaxElapsedSeconds
        $agentHostDllForCatalog = Join-Path $PSScriptRoot 'AgentHost\bin\Release\net8.0\ChronicleAgentHost.dll'
        if (-not (Test-Path -LiteralPath $agentHostDllForCatalog -PathType Leaf)) { throw 'The current Agent Host action catalog is missing; no game was launched.' }
        $catalogOutput = & dotnet $agentHostDllForCatalog --campaign-action-catalog 2>&1 | Out-String
        $catalogExitCode = $LASTEXITCODE
        if ($catalogExitCode -ne 0) { throw "The current Agent Host action catalog could not be read (exit=$catalogExitCode); no game was launched." }
        try { $catalog = $catalogOutput | ConvertFrom-Json }
        catch { throw 'The current Agent Host action catalog returned invalid JSON; no game was launched.' }
        $catalogActions = @($catalog.actions | ForEach-Object { [string]$_ })
        if ($catalogActions.Count -eq 0 -or @($catalogActions | Sort-Object -Unique).Count -ne $catalogActions.Count) {
            throw 'The current Agent Host action catalog is empty or contains duplicate names; no game was launched.'
        }
        $allowedActions = [string]::Join(',', $catalogActions)
        Set-LiveModelProviderTimeout 360
        # Keep the normal MCM Host cap unless the caller explicitly selects a
        # different value for a provider with a larger structured response.
        if ([string]::IsNullOrWhiteSpace($priorModelMaxTokens)) {
            $env:CHRONICLE_LLM_MAX_TOKENS = '256'
        }
        else {
            $env:CHRONICLE_LLM_MAX_TOKENS = $priorModelMaxTokens
        }
    }
    elseif ($EstablishYourClanAutonomyLoop) {
        $finalNativeState = Invoke-AgentCli 'state'
        $initialQuestIds = @($baseline.state.quests | ForEach-Object { [string]$_.id } | Sort-Object)
        $finalQuestIds = @($finalNativeState.state.quests | ForEach-Object { [string]$_.id } | Sort-Object)
        $finalLifecycle = [string]$finalNativeState.state.storyModeEstablishClanStatus.status
        $finalObjectiveIds = @('gold','partySize','renown','companions')
        $unmetFinalObjectives = @($finalObjectiveIds | Where-Object { -not [bool]$loopTrace.objectiveSnapshot.$_.met })
        $allObjectivesMet = ($null -ne $loopTrace.objectiveSnapshot) -and $unmetFinalObjectives.Count -eq 0
        $nativeQuestSucceeded = ([string]$loopTrace.status -ceq 'completed' -and [bool]$loopTrace.termination.goalVerified -and
            [string]$loopTrace.termination.reason -ceq 'native-establish-your-clan-quest-success-verified' -and
            $finalLifecycle -ceq 'completed' -and $finalQuestIds -notcontains 'rebuild_player_clan_storymode_quest')
        $autonomyVerified = [bool]$allObjectivesMet -and $nativeQuestSucceeded
        $autonomyVerification = [ordered]@{
            nativeQuestSucceeded = [bool]$nativeQuestSucceeded
            nativeLifecycleStatus = $finalLifecycle
            originalQuestActiveBefore = ($initialQuestIds -contains 'rebuild_player_clan_storymode_quest')
            originalQuestActiveAfter = ($finalQuestIds -contains 'rebuild_player_clan_storymode_quest')
            allFourFinalJournalObjectivesMet = [bool]$allObjectivesMet
            objectiveRuns = @($loopTrace.objectiveRuns)
            decisionCount = [int]$loopTrace.decisions
            nativeActionCount = [int]$loopTrace.actionsExecuted
            promptTokens = [long]$loopTrace.promptTokens
            completionTokens = [long]$loopTrace.completionTokens
            providerRouteHistory = @($loopTrace.providerRouteHistory)
            completedObjectiveSnapshot = $loopTrace.objectiveSnapshot
            finalLifecycleStatus = $finalLifecycle
            verified = [bool]$autonomyVerified
        }
        $finalObservation = $finalNativeState
        $providerStoppedAfterGoalAction = [bool]$autonomyVerified
        $chosenId = $null
        $chosenTarget = @()
        $observedTargets = @()
        $targetQueries = @()
        $moveSteps = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -eq 'move' })
        $observeSteps = @($steps | Where-Object { $_.control.kind -eq 'bounded-observe-again' })
        $arrivalConfirmed = $null
        $campaignDayAdvancedDuringTravel = $null
        $nativeReadObservationsAfterMove = @()
        $preNativeTravelReobservations = @()
        if (-not $autonomyVerified) { throw 'The real-model StoryMode autonomy run did not verify all four final Journal targets and original Native Quest completion.' }
    }
    elseif ($EstablishYourClanGoalPlanner) {
        $goal = 'Read the active original StoryMode Establish Your Clan quest and choose exactly one currently unmet objective from its four visible numeric goals. Return a planning result only; do not take any game action, modify the quest, claim completion, or change Campaign time.'
        $maxDecisions = 6
        $maxElapsedSeconds = 300
        $allowedActions = 'mapSettlementTargets,move,menuSelect,talkToSettlementHero,dialogueSelect,dialogueContinue,questDetails,tradeOptions,trade,tradeConfirm,tradeCancel,tradeCancelChanges,barterOptions,barterAutoBalance,barterOffer,barterCancel,inventoryOpen,heroEquipmentOptions,inventoryCancel'
        Set-LiveModelProviderTimeout 180
        $env:CHRONICLE_LLM_MAX_TOKENS = '512'
    }
    elseif ($ArrivalLoop) {
        $goal = 'First query mapSettlementTargets. Then choose the nearest observed safe target (not hostile, not under siege, not the current settlement) and issue one move. While party.isMoving toward that target and currentSettlementId differs, use observeAgain with waitSeconds 5; do not send move again or use clock controls. When nativeMoveArrival.status is arrived, return done immediately and issue no further game action.'
        Set-LiveModelProviderTimeout 180
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
        if ($SupplyManagementLoop) {
            $hostRunMode = 'supply-loop'
            $hostRequest = [ordered]@{
                runId = ('agenthost-supply-' + [Guid]::NewGuid().ToString('N'))
                goal = $goal
                targetSettlementId = $chosenSettlementId
                maxDecisions = $maxDecisions
                maxElapsedSeconds = $maxElapsedSeconds
                allowedActionNames = @($allowedActions.Split(',') | ForEach-Object { $_.Trim() })
                completionContract = $completionContractJson | ConvertFrom-Json
            }
        }
        else {
            $hostRunMode = 'campaign-loop'
            $hostNativeHandshake = Invoke-AgentCli 'state'
            if ($hostNativeHandshake.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$hostNativeHandshake.nativeSessionId)) {
                throw 'Campaign Host evaluation requires a fresh Native session handshake.'
            }
            $hostGameProcess = Get-Process -Id ([int]$start.session.processId) -ErrorAction Stop
            $hostRequest = [ordered]@{
                runId = ('agenthost-campaign-' + [Guid]::NewGuid().ToString('N'))
                parentProcessId = [int]$hostGameProcess.Id
                parentProcessStartTimeUtcTicks = $hostGameProcess.StartTime.ToUniversalTime().Ticks
                nativeSessionId = [string]$hostNativeHandshake.nativeSessionId
                goal = $goal
                establishClanPlannerOnly = [bool]$EstablishYourClanGoalPlanner
                maxDecisions = $maxDecisions
                maxElapsedSeconds = $maxElapsedSeconds
                allowedActionNames = @($allowedActions.Split(',') | ForEach-Object { $_.Trim() })
                providerConfiguration = [ordered]@{
                    ProviderBaseUrl = [string]$env:CHRONICLE_LLM_BASE_URL
                    ModelId = [string]$env:CHRONICLE_LLM_MODEL
                    OutputMode = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_OUTPUT_MODE)) { 'auto' } else { [string]$env:CHRONICLE_LLM_OUTPUT_MODE }
                    DeepSeekRunCostLimitCny = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_MAX_RUN_COST_CNY)) { '5' } else { [string]$env:CHRONICLE_LLM_MAX_RUN_COST_CNY }
                }
            }
        }
        $hostStartInfo = [Diagnostics.ProcessStartInfo]::new()
        $hostStartInfo.FileName = (Get-Command dotnet -ErrorAction Stop).Source
        $hostStartInfo.Arguments = '"{0}" --{1}' -f $agentHostDll, $hostRunMode
        $hostStartInfo.UseShellExecute = $false
        $hostStartInfo.CreateNoWindow = $true
        $hostStartInfo.RedirectStandardInput = $true
        $hostStartInfo.RedirectStandardOutput = $true
        $hostStartInfo.RedirectStandardError = $true
        $hostProcess = [Diagnostics.Process]::new()
        $hostProcess.StartInfo = $hostStartInfo
        if (-not $hostProcess.Start()) { throw "Could not start the local Agent Host $hostRunMode." }
        $hostStdoutTask = $hostProcess.StandardOutput.ReadToEndAsync()
        $hostStderrTask = $hostProcess.StandardError.ReadToEndAsync()
        $hostProcess.StandardInput.WriteLine(($hostRequest | ConvertTo-Json -Depth 12 -Compress))
        $hostProcess.StandardInput.Close()
        $hostTimeoutMilliseconds = [int](($maxElapsedSeconds + 60) * 1000)
        if (-not $hostProcess.WaitForExit($hostTimeoutMilliseconds)) {
            try { $hostProcess.Kill() } catch { }
            throw "Local Agent Host $hostRunMode exceeded the bounded process timeout."
        }
        $output = $hostStdoutTask.GetAwaiter().GetResult()
        $outputLines = @($output -split '\r?\n')
        $hostReadyMessages = @($outputLines | Where-Object { $_.StartsWith('CHRONICLE_AGENT_HOST_READY|') })
        $output = ($outputLines | Where-Object { -not $_.StartsWith('CHRONICLE_AGENT_HOST_READY|') }) -join [Environment]::NewLine
        $hostStderr = $hostStderrTask.GetAwaiter().GetResult()
        $loopExitCode = [int]$hostProcess.ExitCode
        if ($loopExitCode -eq 0 -and $hostRunMode -eq 'campaign-loop') {
            $expectedReadyPrefix = 'CHRONICLE_AGENT_HOST_READY|1|' + $hostRequest.parentProcessId + '|' + $hostRequest.runId + '|'
            if (@($hostReadyMessages | Where-Object { $_.StartsWith($expectedReadyPrefix) }).Count -ne 1) {
                throw 'Campaign Host did not return exactly one readiness receipt bound to the current game and run.'
            }
        }
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
    if ($AgentHostRuntime -and -not $agentHostCaptureEventsWritten) {
        $hostProgressPath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentHostProgress.jsonl'
        $captureProjectionSelfTest = Test-ChronicleAgentHostCaptureProjection
        if (-not $captureProjectionSelfTest.Passed) { throw 'AgentHost decision capture projection self-test failed.' }
        $agentHostCaptureDecisionCount = Add-ChronicleAgentHostProgressCaptureEvents $hostProgressPath $eventTracePath ([string]$capture.StartedUtc)
        $agentHostCaptureEventsWritten = $true
    }
    else {
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
    }

    if ($CaptivityRecoveryLoop) {
        $finalNativeState = $loopTrace.finalNativeState
        if (-not $finalNativeState -or -not $finalNativeState.state) { throw 'Captivity Host did not return the final Native state required for post-recovery verification.' }
        $objectiveSelection = $loopTrace.objectiveSelection
        $objectiveSnapshot = $loopTrace.objectiveSnapshot
        $selectedObjectiveId = [string]$objectiveSelection.objectiveId
        $selectedObjective = if ($selectedObjectiveId -and $objectiveSnapshot) { $objectiveSnapshot.$selectedObjectiveId } else { $null }
        $nativeRecoveryActions = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' })
        $battleActions = @($nativeRecoveryActions | Where-Object { $_.actionReceipt.action -in @('mapPartyTargets','pursue','dialogueSelect','battleSkip','battleFinish','partyTakeAll','partyScreenDone','inventoryTakeAll','inventoryDone') })
        $resumeActions = @($nativeRecoveryActions | Where-Object { [string]$_.actionReceipt.action -ceq 'resume' })
        $ransomSteps = @($nativeRecoveryActions | Where-Object { [string]$_.actionReceipt.action -ceq 'menuSelect' })
        $nativeClockActions = @($nativeRecoveryActions | Where-Object { [string]$_.actionReceipt.action -in @('advance','pause','resume','fastForward') } | ForEach-Object { [string]$_.actionReceipt.action })
        $initialStoryQuest = @($baseline.state.quests | Where-Object { [string]$_.id -ceq 'rebuild_player_clan_storymode_quest' })
        $captivityRecoveryVerified = (
            [string]$loopTrace.status -ceq 'completed' -and
            [string]$loopTrace.resultKind -ceq 'captivity-recovered-objective-plan' -and
            [bool]$loopTrace.captivityRecoveryVerified -and
            [bool]$loopTrace.termination.goalVerified -eq $false -and
            [string]$baseline.state.storyModeEstablishClanStatus.status -ceq 'active' -and
            $initialStoryQuest.Count -eq 1 -and
            [bool]$loopTrace.finalStoryModeEstablishClanStatus -and
            [string]$loopTrace.finalStoryModeEstablishClanStatus.status -ceq 'active' -and
            $baseline.state.context.captivity.isCaptive -eq $true -and
            $finalNativeState.state.context.captivity -eq $null -and
            [string]$finalNativeState.state.context.gameState -ceq 'MapState' -and
            [string]::IsNullOrWhiteSpace([string]$finalNativeState.state.context.menuId) -and
            $objectiveSelection -and [string]$selectedObjectiveId -in @('gold','partySize','renown','companions') -and
            [bool]$objectiveSelection.met -eq $false -and $selectedObjective -and [bool]$selectedObjective.met -eq $false -and
            [bool]$loopTrace.targetConsistency.consistent -and
            $resumeActions.Count -ge 1 -and $nativeClockActions.Count -ge 1 -and
            $battleActions.Count -eq 0 -and
            [int]$loopTrace.passiveCaptivityPollCount -ge 1 -and
            [int]$finalNativeState.state.party.members -ge 0
        )
        $finalObservation = $finalNativeState
        $providerStoppedAfterGoalAction = $false
        $chosenId = $null
        $chosenTarget = @()
        $observedTargets = @()
        $targetQueries = @()
        $moveSteps = @()
        $observeSteps = @()
        $nativeMovementObserved = $false
        $arrivalConfirmed = $captivityRecoveryVerified
        $campaignDayAdvancedDuringTravel = $null
        $nativeReadObservationsAfterMove = @()
        $preNativeTravelReobservations = @()
        $plannerVerification = [ordered]@{
            initialCaptivity = $baseline.state.context.captivity
            initialStoryModeStatus = [string]$baseline.state.storyModeEstablishClanStatus.status
            finalStoryModeStatus = [string]$loopTrace.finalStoryModeEstablishClanStatus.status
            finalCaptive = [bool]$finalNativeState.state.context.captivity.isCaptive
            finalCampaignDay = [double]$finalNativeState.campaignDay
            timeModeBefore = [string]$baseline.state.context.timeControlMode
            timeModeAfter = [string]$finalNativeState.state.context.timeControlMode
            explicitClockActions = $nativeClockActions
            nativeActionSequence = @($nativeRecoveryActions | ForEach-Object { [string]$_.actionReceipt.action })
            captivePassivePollCount = [int]$loopTrace.passiveCaptivityPollCount
            mainPartyMembersAtReturn = [int]$finalNativeState.state.party.members
            selectedObjective = $objectiveSelection
            targetConsistency = $loopTrace.targetConsistency
            liveMetricDifferences = $loopTrace.liveMetricDifferences
            goalVerified = [bool]$loopTrace.termination.goalVerified
            passed = [bool]$captivityRecoveryVerified
        }
        if (-not $captivityRecoveryVerified) { throw 'Native captivity recovery did not return a free active StoryMode Campaign Map and replan one still-unmet Establish Your Clan goal.' }
    }
    elseif ($EstablishClanGoldSaleLoop) {
        $saleReceipt = $loopTrace.saleReceipt
        $draftStep = @($steps | Where-Object { $_.actionExecuted -and $_.decision.action -eq 'trade' -and $_.actionReceipt.status -eq 'completed' })
        $confirmStep = @($steps | Where-Object { $_.actionExecuted -and $_.decision.action -eq 'tradeConfirm' -and $_.actionReceipt.status -eq 'completed' })
        $tradeOptionsSteps = @($steps | Where-Object { $_.actionExecuted -and $_.decision.action -eq 'tradeOptions' -and $_.actionReceipt.status -eq 'completed' })
        $mapTargetSteps = @($steps | Where-Object { $_.actionExecuted -and $_.decision.action -eq 'mapSettlementTargets' -and $_.actionReceipt.status -eq 'completed' })
        $moveSteps = @($steps | Where-Object { $_.actionExecuted -and $_.decision.action -eq 'move' -and $_.actionReceipt.status -eq 'completed' })
        $saleBeforeGold = [int]$saleReceipt.playerGoldBefore
        $saleAfterGold = [int]$saleReceipt.playerGoldAfter
        $saleBeforeCount = [int]$saleReceipt.playerCountBefore
        $saleAfterCount = [int]$saleReceipt.playerCountAfter
        $saleOffer = @()
        if ($draftStep.Count -eq 1 -and $tradeOptionsSteps.Count -eq 1) {
            $saleOffer = @($tradeOptionsSteps[0].actionReceipt.data.sellOffers | Where-Object {
                [string]$_.viewModelItemId -ceq [string]$draftStep[0].decision.arguments.ItemViewModelId -and
                [string]$_.inventorySide -ceq 'PlayerInventory' -and [string]$_.nativeTooltipType -ceq 'Goods' -and
                [bool]$_.isTransferable -and [int]$_.stock -ge 1 -and [int]$_.inventoryLogicUnitPrice -gt 0
            } | Select-Object -First 1)
        }
        $saleActions = @($steps | Where-Object { $_.actionExecuted -and $_.decision.action -in @('trade','tradeConfirm') })
        $tradeClockActions = @($saleActions | Where-Object { $_.actionReceipt.data.timeControlModeBefore -ne $_.actionReceipt.data.timeControlModeAfter -or
            [Math]::Abs([double]$_.actionReceipt.data.campaignDayBefore - [double]$_.actionReceipt.data.campaignDayAfter) -gt 0.000001 })
        $captivityRecoveryWasNeeded = [bool]$loopTrace.captivityRecoveryVerified
        $captivityPreludeVerified = (-not [bool]$baseline.state.context.captivity.isCaptive) -or (
            $captivityRecoveryWasNeeded -and [string]$loopTrace.captivityRecoveryResultKind -ceq 'captivity-recovered-objective-plan' -and
            [string]$loopTrace.captivityRecoveryPlannerVerification.finalStoryModeStatus -ceq 'active' -and
            [bool]$loopTrace.captivityRecoveryPlannerVerification.finalCaptive -eq $false
        )
        $saleSettlementId = [string]$saleReceipt.settlementId
        $saleTownObserved = if ($moveSteps.Count -eq 1 -and $mapTargetSteps.Count -eq 1) {
            $moveTargetId = [string]$moveSteps[0].decision.arguments.SettlementId
            $safeTown = @($mapTargetSteps[0].actionReceipt.data.mapSettlementTargets | Where-Object {
                [string]$_.id -ceq $moveTargetId -and [string]$_.type -ceq 'town' -and -not [bool]$_.hostile -and -not [bool]$_.underSiege
            } | Select-Object -First 1)
            ($safeTown.Count -eq 1 -and $saleSettlementId -ceq $moveTargetId)
        } elseif ($moveSteps.Count -eq 0) {
            ([string]$baseline.state.context.menuId -ceq 'town' -and [string]$baseline.state.location.currentSettlementId -ceq $saleSettlementId)
        } else { $false }
        $chosenId = $saleSettlementId
        $chosenTarget = if ($moveSteps.Count -eq 1 -and $mapTargetSteps.Count -eq 1) {
            @($mapTargetSteps[0].actionReceipt.data.mapSettlementTargets | Where-Object { [string]$_.id -ceq $saleSettlementId } | Select-Object -First 1)
        } else {
            @($baseline.state.nearbySettlements | Where-Object { [string]$_.id -ceq $saleSettlementId } | Select-Object -First 1)
        }
        $observedTargets = if ($moveSteps.Count -eq 1 -and $mapTargetSteps.Count -eq 1) { @($mapTargetSteps[0].actionReceipt.data.mapSettlementTargets) } else { @($baseline.state.nearbySettlements) }
        $targetSource = 'current Native safe Town menu or current safe Town targets'
        $nativeMovementObserved = ($moveSteps.Count -eq 1)
        $arrivalConfirmed = $saleTownObserved
        $campaignDayAdvancedDuringTravel = if ($moveSteps.Count -eq 1) { [double]$finalNativeState.campaignDay -gt [double]$moveSteps[0].actionReceipt.campaignDay } else { $null }
        $targetQueries = $mapTargetSteps
        $observeSteps = @($steps | Where-Object { $_.control.kind -eq 'bounded-host-observation' -and -not $_.actionExecuted })
        $nativeReadObservationsAfterMove = @($steps | Where-Object { $_.observationAfter -and $_.observationAfter.state -and [string]$_.observationAfter.state.location.currentSettlementId -ceq $saleSettlementId })
        $preNativeTravelReobservations = @()
        $goldSaleVerified = (
            [string]$loopTrace.status -ceq 'completed' -and [string]$loopTrace.resultKind -ceq 'establish-clan-gold-sale' -and
            [bool]$loopTrace.saleVerified -and [bool]$loopTrace.termination.goalVerified -and
            [string]$baseline.state.storyModeEstablishClanStatus.status -ceq 'active' -and
            [string]$loopTrace.finalNativeState.state.storyModeEstablishClanStatus.status -ceq 'active' -and
            [string]$loopTrace.finalNativeState.state.context.gameState -ceq 'MapState' -and
            $loopTrace.finalNativeState.state.context.captivity -eq $null -and
            $draftStep.Count -eq 1 -and $confirmStep.Count -eq 1 -and $tradeOptionsSteps.Count -eq 1 -and
            [string]$draftStep[0].decision.arguments.Direction -ceq 'sell' -and
            [string]$draftStep[0].decision.arguments.InventorySide -ceq 'PlayerInventory' -and
            [int]$draftStep[0].decision.arguments.Amount -eq 1 -and $saleOffer.Count -eq 1 -and
            [string]$confirmStep[0].actionReceipt.data.itemId -ceq [string]$saleOffer[0].itemId -and
            [int]$confirmStep[0].actionReceipt.data.amount -eq 1 -and
            [bool]$confirmStep[0].actionReceipt.data.postconditionPassed -and $saleAfterGold -gt $saleBeforeGold -and
            ($saleAfterGold - $saleBeforeGold) -eq [Math]::Abs([int]$confirmStep[0].actionReceipt.data.nativeTransactionAmount) -and
            $saleBeforeCount - $saleAfterCount -eq 1 -and
            [double]$loopTrace.initialGoldJournal.current -eq [double]$goldSaleBaseline.JournalGoldCurrent -and
            [double]$loopTrace.finalGoldJournal.current -gt [double]$goldSaleBaseline.JournalGoldCurrent -and
            [double]$loopTrace.finalGoldJournal.target -eq [double]$goldSaleBaseline.JournalGoldTarget -and
            $captivityPreludeVerified -and $tradeClockActions.Count -eq 0 -and
            @($saleActions | Where-Object { $_.decision.action -notin @('trade','tradeConfirm') }).Count -eq 0 -and
            [bool]$loopTrace.originalQuestStillActive -and [bool]$loopTrace.originalQuestCompletionClaimed -eq $false -and
            $saleTownObserved -and $moveSteps.Count -le 1
        )
        $finalObservation = $loopTrace.finalNativeState
        $providerStoppedAfterGoalAction = [bool]$goldSaleVerified
        $goldSaleVerification = [ordered]@{
            objectiveJournalBefore = $goldSaleBaseline
            objectiveJournalAfter = $loopTrace.finalGoldJournal
            liveMetricDifferencesBefore = $loopTrace.liveMetricDifferencesBeforeSale
            liveMetricDifferencesAfter = $loopTrace.liveMetricDifferencesAfterSale
            saleOffer = if ($saleOffer.Count -eq 1) { $saleOffer[0] } else { $null }
            saleReceipt = $saleReceipt
            marketEntryCount = $tradeOptionsSteps.Count
            draftCount = $draftStep.Count
            commitCount = $confirmStep.Count
            amountSold = if ($saleReceipt) { [int]$saleReceipt.amount } else { $null }
            goldBefore = $saleBeforeGold
            goldAfter = $saleAfterGold
            itemCountBefore = $saleBeforeCount
            itemCountAfter = $saleAfterCount
            settlementId = $saleSettlementId
            moveCount = $moveSteps.Count
            mapSettlementQueryCount = $mapTargetSteps.Count
            nativeTradeTimeChanged = ($tradeClockActions.Count -gt 0)
            captivityPreludeVerified = $captivityPreludeVerified
            passed = [bool]$goldSaleVerified
        }
        if (-not $goldSaleVerified) { throw 'Native Gold sale did not produce one current transferable Goods transaction with positive Gold and matching Journal progress.' }
    }
    elseif ($EstablishYourClanGoalPlanner) {
        $finalNativeState = Invoke-AgentCli 'state'
        $selectedObjectiveId = [string]$loopTrace.selection.objectiveId
        $objectiveSnapshot = $loopTrace.objectiveSnapshot
        $selectedObjective = if ($selectedObjectiveId -and $objectiveSnapshot) { $objectiveSnapshot.$selectedObjectiveId } else { $null }
        $initialQuestIds = @($baseline.state.quests | ForEach-Object { [string]$_.id } | Sort-Object)
        $finalQuestIds = @($finalNativeState.state.quests | ForEach-Object { [string]$_.id } | Sort-Object)
        $objectiveIdsFound = @(@('gold','partySize','renown','companions') | Where-Object { $objectiveSnapshot.PSObject.Properties.Name -contains $_ })
        $selectionRouteHistory = @($loopTrace.providerRouteHistory)
        $plannerOnlyTrace = @($steps | Where-Object { $_.planningOnly -eq $true -and $_.nativeActionExecuted -eq $false })
        $plannerChecks = [ordered]@{
            operationCompleted = ([string]$loopTrace.status -ceq 'completed' -and [string]$loopTrace.resultKind -ceq 'objective-plan')
            objectiveSelectionTermination = ([string]$loopTrace.termination.reason -ceq 'unmet-objective-selected')
            wholeQuestNotClaimed = ($loopTrace.termination.goalVerified -eq $false)
            selectionUnmet = ($loopTrace.selection.met -eq $false -and $null -ne $selectedObjective -and $selectedObjective.met -eq $false)
            fourNativeObjectives = ($objectiveIdsFound.Count -eq 4)
            fourVisibleJournalObjectives = ($loopTrace.journalObjectiveSnapshot.Count -eq 4)
            journalTargetsConsistent = ($loopTrace.targetConsistency.consistent -eq $true)
            twoFreeModelRoutes = ($selectionRouteHistory.Count -ge 2)
            onePlannerDecision = ($plannerOnlyTrace.Count -eq 1)
            campaignWasPaused = ([string]$baseline.state.context.timeControlMode -ceq 'Stop')
            campaignDayUnchanged = ([Math]::Abs([double]$baseline.campaignDay - [double]$finalNativeState.campaignDay) -le 0.000001)
            goldUnchanged = ([int]$baseline.state.economy.gold -eq [int]$finalNativeState.state.economy.gold)
            partySizeUnchanged = ([int]$baseline.state.party.members -eq [int]$finalNativeState.state.party.members)
            renownUnchanged = ([double]$baseline.state.economy.renown -eq [double]$finalNativeState.state.economy.renown)
            questSetUnchanged = (($initialQuestIds -join '|') -ceq ($finalQuestIds -join '|'))
            timeModeUnchanged = ([string]$finalNativeState.state.context.timeControlMode -ceq [string]$baseline.state.context.timeControlMode)
            noGameplayActions = (@($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -ne 'questDetails' }).Count -eq 0)
            oneReadOnlyJournalCall = ([int]$loopTrace.actionsExecuted -eq 1)
            activeQuestLifecycleObservedBefore = ([string]$baseline.state.storyModeEstablishClanStatus.status -ceq 'active')
            activeQuestLifecycleObservedAfter = ([string]$finalNativeState.state.storyModeEstablishClanStatus.status -ceq 'active')
        }
        $plannerVerified = @($plannerChecks.GetEnumerator() | Where-Object { -not [bool]$_.Value }).Count -eq 0
        $plannerVerification = [ordered]@{
            sourceCampaignDay = [double]$baseline.campaignDay
            finalCampaignDay = [double]$finalNativeState.campaignDay
            timeModeBefore = [string]$baseline.state.context.timeControlMode
            timeModeAfter = [string]$finalNativeState.state.context.timeControlMode
            goldBefore = [int]$baseline.state.economy.gold
            goldAfter = [int]$finalNativeState.state.economy.gold
            partyMembersBefore = [int]$baseline.state.party.members
            partyMembersAfter = [int]$finalNativeState.state.party.members
            renownBefore = [double]$baseline.state.economy.renown
            renownAfter = [double]$finalNativeState.state.economy.renown
            activeQuestIdsBefore = $initialQuestIds
            activeQuestIdsAfter = $finalQuestIds
            questLifecycleStatusBefore = [string]$baseline.state.storyModeEstablishClanStatus.status
            questLifecycleStatusAfter = [string]$finalNativeState.state.storyModeEstablishClanStatus.status
            gameplayActionCount = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -ne 'questDetails' }).Count
            nativeQuestDetailsReadCount = [int]$loopTrace.actionsExecuted
            selectedObjectiveId = $selectedObjectiveId
            selectedObjectiveCurrent = if ($selectedObjective) { $selectedObjective.current } else { $null }
            selectedObjectiveTarget = if ($selectedObjective) { $selectedObjective.target } else { $null }
            selectedObjectiveMet = if ($selectedObjective) { $selectedObjective.met } else { $null }
            checks = $plannerChecks
            plannerVerified = [bool]$plannerVerified
            goalVerified = [bool]$loopTrace.termination.goalVerified
        }
        $finalObservation = $finalNativeState
        $providerStoppedAfterGoalAction = $false
        $chosenId = $null
        $chosenTarget = @()
        $observedTargets = @()
        $targetQueries = @()
        $moveSteps = @()
        $observeSteps = @()
        $nativeMovementObserved = $false
        $arrivalConfirmed = $false
        $campaignDayAdvancedDuringTravel = $false
        $nativeReadObservationsAfterMove = @()
        $preNativeTravelReobservations = @()
        if (-not $plannerVerified) { throw 'Read-only StoryMode planner did not select exactly one currently unmet objective while preserving Native state and Campaign time.' }
    }
    elseif ($VillageToolsQuestLoop) {
        $lastObservedStep = @($steps | Where-Object { $_.observationAfter -and $_.observationAfter.state } | Select-Object -Last 1)
        $finalObservation = if ($lastObservedStep.Count -eq 1) { $lastObservedStep[0].observationAfter } else { $baseline }
        $questActions = @($steps | Where-Object { $_.actionExecuted } | ForEach-Object { [string]$_.actionReceipt.action })
        $nativeClockActions = [object[]]@($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -in @('advance','pause','resume','fastForward') })
        $questVerified = ([string]$loopTrace.status -eq 'completed' -and [bool]$loopTrace.questWasObservedActive -and
            [bool]$loopTrace.inventoryVerifiedAfterTurnIn -and [bool]$loopTrace.termination.goalVerified -and $nativeClockActions.Count -eq 0 -and
            $questActions.Contains('questDetails') -and $questActions.Contains('tradeOptions') -and $questActions.Contains('trade') -and
            $questActions.Contains('tradeConfirm') -and $questActions.Contains('talkToSettlementHero') -and $questActions.Contains('dialogueSelect') -and
            $questActions.Contains('inventoryOpen') -and $questActions.Contains('heroEquipmentOptions') -and $questActions.Contains('inventoryCancel'))
        $providerStoppedAfterGoalAction = $questVerified
        $chosenId = [string]$loopTrace.questId
        $chosenTarget = @([pscustomobject]@{ id = $chosenId; name = 'Native VillageNeedsTools issue' })
        $observedTargets = @()
        $targetQueries = @($steps | Where-Object { $_.decision.action -eq 'mapSettlementTargets' -and $_.actionReceipt.status -eq 'completed' })
        $observeSteps = @($steps | Where-Object { $_.control.kind -eq 'bounded-observe-again' })
        $arrivalConfirmed = $questVerified
        $campaignDayAdvancedDuringTravel = $null
        $nativeMovementObserved = ($questActions -contains 'move')
        $nativeReadObservationsAfterMove = @()
        $preNativeTravelReobservations = @()
        $chosenObservedSafeTarget = $null
        if (-not $questVerified) { throw 'Host live-model VillageNeedsTools task lacked the complete Native Quest plus exact Inventory delta postconditions.' }
    }
    elseif ($SupplyManagementLoop) {
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
        $naturalCampaignTimeAdvanced = [double]$finalObservation.campaignDay -gt [double]$supplySetup.CampaignDay
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
            $naturalTicksElapsed -eq 3 -and $naturalCampaignTimeAdvanced -and
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
                CampaignDayDelta = [Math]::Round(([double]$finalObservation.campaignDay - [double]$supplySetup.CampaignDay), 4)
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
    elseif ($BattleSimulationLoop -or $BattleAndCaptivityLoop) {
        $finalNativeState = $loopTrace.finalNativeState
        if (-not $finalNativeState -or -not $finalNativeState.state) { throw 'Battle Host did not return the final Native state needed for result and evidence verification.' }
        $finalObservation = [ordered]@{ status = 'completed'; campaignDay = [double]$finalNativeState.campaignDay; dailyTickCount = $null; timeControlMode = [string]$finalNativeState.timeControlMode; state = $finalNativeState.state }
        $battleTargetId = [string]$loopTrace.targetPartyId
        $targetQueries = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -eq 'mapPartyTargets' -and $_.actionReceipt.status -eq 'completed' })
        $targetObservation = @($targetQueries | ForEach-Object { $_.actionReceipt.data.mapPartyTargets } | Where-Object { $_.id -ceq $battleTargetId -and $_.type -ceq 'bandit' -and $_.hostile -eq $true } | Select-Object -First 1)
        $chosenTarget = @($targetObservation)
        $chosenId = $battleTargetId
        $chosenObservedSafeTarget = ($chosenTarget.Count -eq 1)
        $observedTargets = @($targetObservation)
        $targetSource = 'current Native mapPartyTargets hostile Bandit candidate; no seeded party or hidden global target'
        $moveSteps = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -eq 'pursue' -and $_.actionReceipt.status -eq 'completed' })
        $nativeMovementObserved = ($moveSteps.Count -gt 0)
        $arrivalConfirmed = $null
        $campaignDayAdvancedDuringTravel = if ($moveSteps.Count -gt 0) { [double]$finalObservation.campaignDay -gt [double]$moveSteps[0].actionReceipt.campaignDay } else { $false }
        $observeSteps = @($steps | Where-Object { $_.decision.observeAgain -eq $true -and $_.observationAfter.status -eq 'completed' })
        $nativeReadObservationsAfterMove = @()
        $preNativeTravelReobservations = @()

        $nativeClockActions = [object[]]@($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -in @('advance','pause','resume','fastForward') })
        $fightDialogue = @($steps | Where-Object {
            $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' -and
            $_.decision.action -eq 'dialogueSelect' -and [string]$_.decision.arguments.OptionId -ceq 'bandit_start_defender_1' -and
            [bool]$_.observationBefore.state.context.encounterActive -and
            [string]$_.observationBefore.state.context.encounteredPartyId -ceq $battleTargetId -and
            @($_.observationBefore.state.context.conversation.options | Where-Object { $_.id -ceq 'bandit_start_defender_1' -and $_.clickable }).Count -eq 1
        })
        $sendTroops = @($steps | Where-Object {
            $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' -and
            $_.decision.action -eq 'menuSelect' -and [string]$_.decision.arguments.OptionId -ceq 'str_order_attack' -and
            [bool]$_.observationBefore.state.context.encounterActive -and
            [string]$_.observationBefore.state.context.menuId -ceq 'encounter' -and
            [string]$_.observationBefore.state.context.encounteredPartyId -ceq $battleTargetId -and
            @($_.observationBefore.state.availableMenuOptions | Where-Object { $_.id -ceq 'str_order_attack' -and $_.available -and $_.enabled }).Count -eq 1
        })
        $battleSkips = @($steps | Where-Object {
            $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' -and $_.decision.action -eq 'battleSkip' -and
            $_.observationBefore.state.context.battleSimulation -and -not [bool]$_.observationBefore.state.context.battleSimulation.finished
        })
        $battleSkipAttempts = @($steps | Where-Object { $_.actionAttempted -and $_.decision.action -eq 'battleSkip' })
        $battleSkipRaceToFinished = @($steps | Where-Object {
            $_.decision.action -eq 'battleSkip' -and [string]$_.actionReceipt.error -match 'requires an unfinished native battle simulation' -and
            [bool]$_.observationAfter.state.context.battleSimulation.finished
        })
        $battleFinishes = @($steps | Where-Object {
            $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' -and $_.decision.action -eq 'battleFinish' -and
            $_.observationBefore.state.context.battleSimulation -and [bool]$_.observationBefore.state.context.battleSimulation.finished
        })
        $partyLootObservations = @($steps | Where-Object { [string]$_.observationBefore.state.partyScreen.mode -eq 'Loot' })
        $inventoryLootObservations = @($steps | Where-Object { [string]$_.observationBefore.state.inventoryScreen.mode -eq 'Loot' })
        $partyTakeActions = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' -and $_.decision.action -eq 'partyTakeAll' })
        $inventoryTakeActions = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' -and $_.decision.action -eq 'inventoryTakeAll' })
        $partyDoneActions = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' -and $_.decision.action -eq 'partyScreenDone' })
        $inventoryDoneActions = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' -and $_.decision.action -eq 'inventoryDone' })
        $partyLootHandled = ($partyLootObservations.Count -eq 0 -or $partyDoneActions.Count -gt 0)
        $inventoryLootHandled = ($inventoryLootObservations.Count -eq 0 -or $inventoryDoneActions.Count -gt 0)
        $renownBefore = [double]$loopTrace.renownBefore
        $renownAfter = [double]$loopTrace.renownAfter
        $providerStoppedAfterGoalAction = (
            [string]$loopTrace.status -eq 'completed' -and
            [string]$loopTrace.termination -eq $(if ($BattleAndCaptivityLoop) { 'battle-and-captivity-resolved-and-verified' } else { 'battle-resolved-and-verified' }) -and
            [bool]$loopTrace.nativeReturnToMapVerified -and
            $steps.Count -gt 0 -and [bool]$steps[-1].decision.done
        )
        $battleSimulationVerified = (
            $providerStoppedAfterGoalAction -and $chosenObservedSafeTarget -and
            (($fightDialogue.Count -eq 1 -and $sendTroops.Count -eq 1) -or ($fightDialogue.Count -eq 0 -and $sendTroops.Count -eq 1)) -and
            $battleFinishes.Count -eq 1 -and $partyLootHandled -and $inventoryLootHandled -and
            -not [double]::IsNaN($renownBefore) -and -not [double]::IsInfinity($renownBefore) -and
            -not [double]::IsNaN($renownAfter) -and -not [double]::IsInfinity($renownAfter) -and $nativeClockActions.Count -eq 0 -and
            (-not $BattleAndCaptivityLoop -or ([bool]$loopTrace.captivityObserved -and [bool]$loopTrace.captivityRecoveryVerified -and [string]$loopTrace.playerOutcome -ceq 'captured-then-recovered'))
        )
        $battleOutcome = [ordered]@{
            TargetPartyId = $battleTargetId
            TargetParty = if ($chosenTarget.Count -eq 1) { $chosenTarget[0] } else { $null }
            EncounterFightDialogue = if ($fightDialogue.Count -eq 1) { [string]$fightDialogue[0].decision.arguments.OptionId } else { $null }
            SendTroopsOption = if ($sendTroops.Count -eq 1) { [string]$sendTroops[0].decision.arguments.OptionId } else { $null }
            SimulationState = [string]$loopTrace.battleState
            BattleFinishReceipt = $loopTrace.battleFinishReceipt
            BattleSkipAttemptCount = $battleSkipAttempts.Count
            BattleSkipCompletedCount = $battleSkips.Count
            BattleSkipRacedWithNativeCompletionCount = $battleSkipRaceToFinished.Count
            PlayerRetreated = [bool]$loopTrace.playerRetreated
            PartyLootScreenCount = $partyLootObservations.Count
            PartyTakeAllCount = $partyTakeActions.Count
            InventoryLootScreenCount = $inventoryLootObservations.Count
            InventoryTakeAllCount = $inventoryTakeActions.Count
            PlayerOutcome = [string]$loopTrace.playerOutcome
            PlayerCaptiveAtMapReturn = [bool]$loopTrace.playerCaptiveAtMapReturn
            NativeMapReturnMenuId = [string]$loopTrace.nativeMapReturnMenuId
            FreeMapReturned = [bool]$loopTrace.freeMapReturned
            CaptivityRecoveryRequested = [bool]$loopTrace.captivityRecoveryRequested
            CaptivityObserved = [bool]$loopTrace.captivityObserved
            CaptivityChoiceOptionId = [string]$loopTrace.captivityChoiceOptionId
            CaptivityRecoveryVerified = [bool]$loopTrace.captivityRecoveryVerified
            MainPartyMembersAtReturn = [int]$loopTrace.mainPartyMembersAtReturn
            RenownBefore = $renownBefore
            RenownAfter = $renownAfter
            RenownDelta = [Math]::Round(($renownAfter - $renownBefore), 4)
            OutcomeBefore = $loopTrace.outcomeBefore
            OutcomeAfter = $loopTrace.outcomeAfter
            NativeReturnToMapVerified = [bool]$loopTrace.nativeReturnToMapVerified
            ExplicitClockActionCount = $nativeClockActions.Count
        }
        if (-not $battleSimulationVerified) { throw 'Real model did not complete the configured Native battle slice, process its actual aftermath, verify post-battle state and any required captivity recovery, and return to a usable Campaign Map.' }
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
    $captureResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactSheetPath -EventTracePath $eventTracePath
    $capture = $null

    $liveModelTrace = [ordered]@{
        ProviderKind = 'configured live model provider'
        ProviderProtocol = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_PROTOCOL)) { 'openai-compatible' } else { [string]$env:CHRONICLE_LLM_PROTOCOL }
        ModelId = if ($AgentHostRuntime -and $loopTrace.providerModelId) { [string]$loopTrace.providerModelId } else { [string]$env:CHRONICLE_LLM_MODEL }
        ModelConfigurationSource = if ($AgentHostRuntime) { [string]$loopTrace.providerConfigurationSource } else { 'environment-provider' }
        ProviderRouteHistory = if ($AgentHostRuntime) { $loopTrace.providerRouteHistory } else { $null }
        AgentHostCaptureDecisionEvents = $agentHostCaptureDecisionCount
        CaptureRecoveryProof = $captureRecoveryProof
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
        AcceptanceSlice = if ($EstablishYourClanAutonomyLoop) { 'Real-model Native autonomous pursuit of all four original Establish Your Clan objectives and original Quest completion (this fixture run is not the two-fresh-campaign product gate)' } elseif ($EstablishClanGoldSaleLoop) { 'Real-model Native StoryMode Gold objective progress through one market sale' } elseif ($CaptivityRecoveryLoop) { 'Real-model Native recovery from existing StoryMode MainHero captivity followed by objective replanning' } elseif ($EstablishYourClanGoalPlanner) { 'Real-model read-only selection of one unmet original StoryMode Establish Your Clan objective' } elseif ($BattleAndCaptivityLoop) { 'Real-model Native hostile Bandit BattleSimulation and MainHero captivity recovery to Campaign Map' } elseif ($BattleSimulationLoop) { 'Real-model Native hostile Bandit meeting/Fight, Send Troops BattleSimulation, aftermath and Renown verification' } elseif ($VillageToolsQuestLoop) { 'Real-model Native VillageNeedsTools quest acceptance, delivery and exact inventory delta' } elseif ($SupplyManagementLoop) { 'Real-model Native food purchase and three-day Town Wait' } elseif ($RoadsideBanditNegotiationLoop) { 'Native roadside Safe Passage, recovery, and volunteer recruitment' } elseif ($RecruitmentLoop) { 'Native movement plus volunteer recruitment' } elseif ($ArrivalLoop) { 'Native movement arrival' } else { 'Native movement order accepted' }
        SafePassageRoute = $safePassageRoute
        HarnessWorldEvents = @($loopTrace.harnessEvents)
        ChosenSettlementId = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { $null } else { $chosenId }
        ChosenSettlementName = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop -or -not $chosenTarget -or @($chosenTarget).Count -eq 0) { $null } else { [string]$chosenTarget[0].name }
        ObservedTargetCount = $observedTargets.Count
        QueryThenNativeMoveVerified = if ($EstablishClanGoldSaleLoop) { $goldSaleVerified -and ($moveSteps.Count -eq 0 -or $nativeMovementObserved) } else { (-not ($SupplyManagementLoop -or $VillageToolsQuestLoop -or $BattleSimulationLoop -or $BattleAndCaptivityLoop -or $CaptivityRecoveryLoop -or $EstablishYourClanGoalPlanner -or $EstablishYourClanAutonomyLoop)) }
        EstablishYourClanAutonomyLoopVerified = if ($EstablishYourClanAutonomyLoop) { [bool]$autonomyVerified } else { $null }
        EstablishYourClanAutonomyVerification = if ($EstablishYourClanAutonomyLoop) { $autonomyVerification } else { $null }
        ChosenTargetSource = $targetSource
        ArrivalConfirmed = $arrivalConfirmed
        BoundedReobservations = $observeSteps.Count
        NativeReadObservationsAfterMove = $nativeReadObservationsAfterMove.Count
        NativeTravelReobservations = ($observeSteps.Count + $preNativeTravelReobservations.Count)
        CampaignDayAdvancedDuringTravel = $campaignDayAdvancedDuringTravel
        RecruitmentVerified = if ($RecruitmentLoop) { [bool]$nativeRecruitmentVerified } else { $null }
        VillageToolsQuestVerified = if ($VillageToolsQuestLoop) { [bool]$questVerified } else { $null }
        VillageToolsQuestId = if ($VillageToolsQuestLoop) { [string]$loopTrace.questId } else { $null }
        VillageToolsQuestInventoryDeltaVerified = if ($VillageToolsQuestLoop) { [bool]$loopTrace.inventoryVerifiedAfterTurnIn } else { $null }
        EstablishYourClanPlannerVerified = if ($EstablishYourClanGoalPlanner) { [bool]$plannerVerified } else { $null }
        EstablishYourClanObjectiveSelection = if ($EstablishYourClanGoalPlanner) { $loopTrace.selection } else { $null }
        EstablishYourClanObjectiveSnapshot = if ($EstablishYourClanGoalPlanner) { $loopTrace.objectiveSnapshot } else { $null }
        EstablishYourClanJournalObjectiveSnapshot = if ($EstablishYourClanGoalPlanner) { $loopTrace.journalObjectiveSnapshot } else { $null }
        EstablishYourClanPlannerVerification = if ($EstablishYourClanGoalPlanner) { $plannerVerification } else { $null }
        EstablishYourClanQuestDetails = if ($EstablishYourClanGoalPlanner) { $loopTrace.questDetails } else { $null }
        EstablishYourClanTargetConsistency = if ($EstablishYourClanGoalPlanner) { $loopTrace.targetConsistency } else { $null }
        EstablishYourClanQuestStatusBefore = if ($EstablishYourClanGoalPlanner) { [string]$baseline.state.storyModeEstablishClanStatus.status } else { $null }
        EstablishYourClanQuestStatusAfter = if ($EstablishYourClanGoalPlanner -and $finalObservation) { [string]$finalObservation.state.storyModeEstablishClanStatus.status } else { $null }
        EstablishYourClanGoalVerified = if ($EstablishYourClanGoalPlanner) { [bool]$loopTrace.termination.goalVerified } else { $null }
        EstablishClanGoldSaleVerified = if ($EstablishClanGoldSaleLoop) { [bool]$goldSaleVerified } else { $null }
        EstablishClanGoldSaleVerification = $goldSaleVerification
        EstablishClanGoldSaleBaseline = if ($EstablishClanGoldSaleLoop) { $goldSaleBaseline } else { $null }
        CaptivityRecoveryVerified = if ($CaptivityRecoveryLoop) { [bool]$captivityRecoveryVerified } elseif ($BattleAndCaptivityLoop) { [bool]$loopTrace.captivityRecoveryVerified } else { $null }
        CaptivityRecoveryChoiceOptionId = if ($CaptivityRecoveryLoop) { [string]$loopTrace.captivityChoiceOptionId } else { $null }
        CaptivityRecoveryFinalState = if ($CaptivityRecoveryLoop) { $loopTrace.finalNativeState.state.context } else { $null }
        CaptivityRecoveryResultKind = if ($CaptivityRecoveryLoop) { [string]$loopTrace.resultKind } else { $null }
        CaptivityRecoveryObjectiveSelection = if ($CaptivityRecoveryLoop) { $loopTrace.objectiveSelection } else { $null }
        CaptivityRecoveryPlannerStatus = if ($CaptivityRecoveryLoop) { [string]$loopTrace.status } else { $null }
        CaptivityRecoveryPlannerResultKind = if ($CaptivityRecoveryLoop) { [string]$loopTrace.resultKind } else { $null }
        CaptivityRecoveryObjectiveSnapshot = if ($CaptivityRecoveryLoop) { $loopTrace.objectiveSnapshot } else { $null }
        CaptivityRecoveryJournalObjectiveSnapshot = if ($CaptivityRecoveryLoop) { $loopTrace.journalObjectiveSnapshot } else { $null }
        CaptivityRecoveryTargetConsistency = if ($CaptivityRecoveryLoop) { $loopTrace.targetConsistency } else { $null }
        CaptivityRecoveryLiveMetricDifferences = if ($CaptivityRecoveryLoop) { $loopTrace.liveMetricDifferences } else { $null }
        CaptivityRecoveryPlannerTermination = if ($CaptivityRecoveryLoop) { $loopTrace.termination } else { $null }
        CaptivityRecoveryPlannerVerification = if ($CaptivityRecoveryLoop) { $plannerVerification } else { $null }
        BattleSimulationVerified = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { [bool]$battleSimulationVerified } else { $null }
        BattleOutcome = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { $battleOutcome } else { $null }
        BattleRenownBefore = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { [double]$loopTrace.renownBefore } else { $null }
        BattleRenownAfter = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { [double]$loopTrace.renownAfter } else { $null }
        BattleReturnToMapVerified = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { [bool]$loopTrace.nativeReturnToMapVerified } else { $null }
        NativeClockActions = @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -in @('advance','pause','resume','fastForward') } | ForEach-Object { [string]$_.actionReceipt.action })
        SupplyFixtureSetup = $supplySetup
        SupplyVerified = if ($SupplyManagementLoop) { [bool]$supplyVerified } else { $null }
        SupplyVerification = $supplyVerification
        SupplyNativeClockActions = if ($SupplyManagementLoop) { @($steps | Where-Object { $_.actionExecuted -and $_.actionReceipt.action -in @('advance','pause','resume','fastForward') } | ForEach-Object { [string]$_.actionReceipt.action }) } else { @() }
        ProviderStoppedAfterGoalAction = $providerStoppedAfterGoalAction
        ProviderBudget = $loopTrace.providerBudget
        HostFailureStage = $loopTrace.failureStage
        HostFailureExceptionType = $loopTrace.failureExceptionType
        HostFailureDetail = if (-not [string]::IsNullOrWhiteSpace([string]$loopTrace.failureDetail)) { [string]$loopTrace.failureDetail } elseif (-not [string]::IsNullOrWhiteSpace([string]$loopTrace.failure)) { ([string]$loopTrace.failure).Substring(0, [Math]::Min(600, ([string]$loopTrace.failure).Length)) } elseif (-not [string]::IsNullOrWhiteSpace([string]$loopTrace.message)) { ([string]$loopTrace.message).Substring(0, [Math]::Min(600, ([string]$loopTrace.message).Length)) } else { $null }
        HostFailureStack = $loopTrace.failureStack
        HostLastSelectedAction = $loopTrace.lastSelectedAction
        HostFailureCode = if ($loopTrace.failureCode) { [string]$loopTrace.failureCode } elseif ($loopTrace.error) { [string]$loopTrace.error } else { $null }
        HostTerminationReason = if ($loopTrace.termination) { [string]$loopTrace.termination.reason } else { $null }
        HostUnimplementedObjectives = @($loopTrace.unimplementedObjectives)
        HostObjectiveRuns = @($loopTrace.objectiveRuns)
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
            SourceVideoPath = if ($captureResult.VideoRemovedAfterEvidence) { $null } else { $videoPath }
            SourceVideoRemovedAfterKeyframes = [bool]$captureResult.VideoRemovedAfterEvidence
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
            ModelConfigurationSource = if ($AgentHostRuntime -and $loopTrace) { [string]$loopTrace.providerConfigurationSource } else { 'failed-before-provider-loop' }
            ProviderRouteHistory = if ($AgentHostRuntime -and $loopTrace) { $loopTrace.providerRouteHistory } else { $null }
            AgentHostCaptureDecisionEvents = $agentHostCaptureDecisionCount
            CaptureRecoveryProof = $captureRecoveryProof
            ModelMaxOutputTokens = if ($loopTrace.providerBudget) { [int]$loopTrace.providerBudget.maxOutputTokensPerCall } else { [int]$env:CHRONICLE_LLM_MAX_TOKENS }
            ModelThinkingMode = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_THINKING_MODE)) { 'provider-default' } else { [string]$env:CHRONICLE_LLM_THINKING_MODE }
            ModelReasoningEffort = if ([string]::IsNullOrWhiteSpace([string]$env:CHRONICLE_LLM_REASONING_EFFORT)) { 'provider-default' } else { [string]$env:CHRONICLE_LLM_REASONING_EFFORT }
            SourceCommit = $sourceCommit
            SourceTrackedTreeClean = $sourceTrackedTreeClean
            ProviderBudget = $loopTrace.providerBudget
            HostFailureStage = $loopTrace.failureStage
            HostFailureExceptionType = $loopTrace.failureExceptionType
            HostFailureDetail = if (-not [string]::IsNullOrWhiteSpace([string]$loopTrace.failureDetail)) { [string]$loopTrace.failureDetail } elseif (-not [string]::IsNullOrWhiteSpace([string]$loopTrace.failure)) { ([string]$loopTrace.failure).Substring(0, [Math]::Min(600, ([string]$loopTrace.failure).Length)) } elseif (-not [string]::IsNullOrWhiteSpace([string]$loopTrace.message)) { ([string]$loopTrace.message).Substring(0, [Math]::Min(600, ([string]$loopTrace.message).Length)) } else { $null }
            HostFailureStack = $loopTrace.failureStack
            HostLastSelectedAction = $loopTrace.lastSelectedAction
            HostFailureCode = if ($loopTrace.failureCode) { [string]$loopTrace.failureCode } elseif ($loopTrace.error) { [string]$loopTrace.error } else { $null }
            HostTerminationReason = if ($loopTrace.termination) { [string]$loopTrace.termination.reason } else { $null }
            HostUnimplementedObjectives = @($loopTrace.unimplementedObjectives)
            HostObjectiveRuns = @($loopTrace.objectiveRuns)
            RunStartedUtc = $modelRunStartedUtc
            RunCompletedUtc = [DateTime]::UtcNow.ToString('O')
            CampaignDayStart = if ($baseline) { [double]$baseline.campaignDay } else { $null }
            CampaignDayEnd = if ($loopTrace.lastObservation) { [double]$loopTrace.lastObservation.campaignDay } else { $null }
            Goal = $goal
            AcceptanceSlice = if ($EstablishYourClanAutonomyLoop) { 'Real-model Native autonomous EYC objective loop did not reach verified original Quest completion on this fixture' } elseif ($EstablishClanGoldSaleLoop) { 'Real-model Native StoryMode Gold objective sale' } elseif ($CaptivityRecoveryLoop) { 'Real-model Native recovery from existing StoryMode MainHero captivity followed by objective replanning' } elseif ($EstablishYourClanGoalPlanner) { 'Real-model read-only selection of one unmet original StoryMode Establish Your Clan objective' } elseif ($BattleAndCaptivityLoop) { 'Failed real-model Native BattleSimulation/captivity recovery' } elseif ($BattleSimulationLoop) { 'Failed real-model Native Bandit BattleSimulation' } elseif ($VillageToolsQuestLoop) { 'Failed real-model Native VillageNeedsTools Quest' } elseif ($SupplyManagementLoop) { 'Real-model Native food purchase and three-day Town Wait' } else { 'Failed live-model decision loop' }
            EstablishClanGoldSaleVerified = if ($EstablishClanGoldSaleLoop) { [bool]$goldSaleVerified } else { $null }
            EstablishClanGoldSaleVerification = $goldSaleVerification
            EstablishClanGoldSaleBaseline = if ($EstablishClanGoldSaleLoop -and $goldSaleBaseline) { $goldSaleBaseline } else { $null }
            CaptivityRecoveryVerified = if ($CaptivityRecoveryLoop) { [bool]$captivityRecoveryVerified } else { $null }
            CaptivityRecoveryChoiceOptionId = if ($CaptivityRecoveryLoop -and $loopTrace) { [string]$loopTrace.captivityChoiceOptionId } else { $null }
            CaptivityRecoveryFinalState = if ($CaptivityRecoveryLoop -and $loopTrace) { $loopTrace.finalNativeState.state.context } else { $null }
            CaptivityRecoveryObjectiveSelection = if ($CaptivityRecoveryLoop -and $loopTrace) { $loopTrace.objectiveSelection } else { $null }
            CaptivityRecoveryPlannerStatus = if ($CaptivityRecoveryLoop -and $loopTrace) { [string]$loopTrace.status } else { $null }
            CaptivityRecoveryPlannerResultKind = if ($CaptivityRecoveryLoop -and $loopTrace) { [string]$loopTrace.resultKind } else { $null }
            CaptivityRecoveryObjectiveSnapshot = if ($CaptivityRecoveryLoop -and $loopTrace) { $loopTrace.objectiveSnapshot } else { $null }
            CaptivityRecoveryJournalObjectiveSnapshot = if ($CaptivityRecoveryLoop -and $loopTrace) { $loopTrace.journalObjectiveSnapshot } else { $null }
            CaptivityRecoveryTargetConsistency = if ($CaptivityRecoveryLoop -and $loopTrace) { $loopTrace.targetConsistency } else { $null }
            CaptivityRecoveryLiveMetricDifferences = if ($CaptivityRecoveryLoop -and $loopTrace) { $loopTrace.liveMetricDifferences } else { $null }
            CaptivityRecoveryPlannerTermination = if ($CaptivityRecoveryLoop -and $loopTrace) { $loopTrace.termination } else { $null }
            CaptivityRecoveryPlannerVerification = if ($CaptivityRecoveryLoop) { $plannerVerification } else { $null }
            EstablishYourClanPlannerVerified = if ($EstablishYourClanGoalPlanner) { [bool]$plannerVerified } else { $null }
            EstablishYourClanObjectiveSelection = if ($EstablishYourClanGoalPlanner -and $loopTrace) { $loopTrace.selection } else { $null }
            EstablishYourClanObjectiveSnapshot = if ($EstablishYourClanGoalPlanner -and $loopTrace) { $loopTrace.objectiveSnapshot } else { $null }
            EstablishYourClanJournalObjectiveSnapshot = if ($EstablishYourClanGoalPlanner -and $loopTrace) { $loopTrace.journalObjectiveSnapshot } else { $null }
            EstablishYourClanPlannerVerification = if ($EstablishYourClanGoalPlanner) { $plannerVerification } else { $null }
            EstablishYourClanTargetConsistency = if ($EstablishYourClanGoalPlanner -and $loopTrace) { $loopTrace.targetConsistency } else { $null }
            EstablishYourClanQuestStatusBefore = if ($EstablishYourClanGoalPlanner -and $baseline) { [string]$baseline.state.storyModeEstablishClanStatus.status } else { $null }
            EstablishYourClanQuestStatusAfter = if ($EstablishYourClanGoalPlanner -and $finalObservation) { [string]$finalObservation.state.storyModeEstablishClanStatus.status } else { $null }
            EstablishYourClanGoalVerified = if ($EstablishYourClanGoalPlanner -and $loopTrace) { [bool]$loopTrace.termination.goalVerified } else { $null }
            EstablishYourClanAutonomyLoopVerified = if ($EstablishYourClanAutonomyLoop) { [bool]$autonomyVerified } else { $null }
            EstablishYourClanAutonomyVerification = if ($EstablishYourClanAutonomyLoop) { $autonomyVerification } else { $null }
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
            if ($AgentHostRuntime -and -not $agentHostCaptureEventsWritten) {
                $hostProgressPath = Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentHostProgress.jsonl'
                $captureProjectionSelfTest = Test-ChronicleAgentHostCaptureProjection
                if (-not $captureProjectionSelfTest.Passed) { throw 'AgentHost decision capture projection self-test failed.' }
                $agentHostCaptureDecisionCount = Add-ChronicleAgentHostProgressCaptureEvents $hostProgressPath $eventTracePath ([string]$capture.StartedUtc)
                $agentHostCaptureEventsWritten = $true
            }
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
            $captureResult = Stop-ChronicleWindowVideoCapture -Capture $capture -ContactSheetPath $contactSheetPath -EventTracePath $eventTracePath
        }
        catch {
            [ordered]@{ stoppedUtc = (Get-Date).ToUniversalTime().ToString('O'); error = $_.Exception.Message; videoPath = $videoPath; eventTracePath = $eventTracePath } |
                ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDirectory 'LiveModelWindow-partial.json') -Encoding UTF8
            try { if ($capture.Process -and -not $capture.Process.HasExited) { $capture.Process.Kill() } } catch { }
        }
        $capture = $null
    }
    if ($CheckpointSaveName -and $sessionStarted) {
        $checkpointSaveOwned = $true
        try {
            $checkpointState = Invoke-AgentCli 'state'
            $checkpointNativeState = $checkpointState.state
            $checkpointContext = $checkpointNativeState.context
            $checkpointLocation = $checkpointNativeState.location
            $checkpointCurrentSettlementId = [string]$checkpointLocation.currentSettlementId
            $checkpointSaveStateDisposition = Get-NativeCheckpointStateDisposition $checkpointState
            if ([string]::IsNullOrWhiteSpace([string]$checkpointSaveStateDisposition)) {
                throw "A persistent EYC checkpoint requires a stable Native Campaign Map or a safe non-sieged settlement menu; current state=$($checkpointContext.gameState), menu=$($checkpointContext.menuId), encounter=$($checkpointContext.encounterActive), settlement=$checkpointCurrentSettlementId."
            }
            $checkpointSave = Invoke-AgentCli 'save' @('-SaveName', $CheckpointSaveName, '-CommandId', ('eyc-continuous-checkpoint-' + [Guid]::NewGuid().ToString('N')))
            if ($checkpointSave.status -ne 'completed') { throw 'Native SaveAs did not return a successful OnSaveOver receipt for the EYC checkpoint.' }
            if (-not (Test-Path -LiteralPath $checkpointSavePath -PathType Leaf) -or (Get-Item -LiteralPath $checkpointSavePath).Length -lt 4096) {
                throw 'Native SaveAs returned success, but the new EYC checkpoint file is missing or incomplete.'
            }
            $checkpointSaveHash = (Get-FileHash -LiteralPath $checkpointSavePath -Algorithm SHA256).Hash
            $checkpointSaveCompleted = $true
        }
        catch {
            $checkpointSaveFailure = $_.Exception.Message
            if (-not $failure) { $failure = "Persistent EYC checkpoint failed: $checkpointSaveFailure" }
        }
    }
    if ($sessionStarted -or (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
        try { $stop = Invoke-AgentCli 'stop' } catch { if (-not $failure) { $failure = "Agent session cleanup failed: $($_.Exception.Message)" } }
    }
    if ($checkpointSaveOwned -and -not $checkpointSaveCompleted -and (Test-Path -LiteralPath $checkpointSavePath -PathType Leaf)) {
        $saveRoot = [IO.Path]::GetFullPath((Join-Path $documentsRoot 'Game Saves')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $fullCheckpointPath = [IO.Path]::GetFullPath($checkpointSavePath)
        if (-not $fullCheckpointPath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Failed EYC checkpoint cleanup path escaped Game Saves.' }
        Remove-Item -LiteralPath $fullCheckpointPath -Force
    }
    if ($null -eq $priorHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $priorHarnessMode }
    if ($null -eq $priorHarnessAgentInputLock) { Remove-Item Env:CHRONICLE_HARNESS_AGENT_INPUT_LOCK -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_AGENT_INPUT_LOCK = $priorHarnessAgentInputLock }
    if ($null -eq $priorModelTimeout) { Remove-Item Env:CHRONICLE_LLM_TIMEOUT_SECONDS -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_LLM_TIMEOUT_SECONDS = $priorModelTimeout }
    if ($null -eq $priorModelMaxTokens) { Remove-Item Env:CHRONICLE_LLM_MAX_TOKENS -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_LLM_MAX_TOKENS = $priorModelMaxTokens }
    if ($null -eq $priorModelMaxHttpRequests) { Remove-Item Env:CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_LLM_MAX_HTTP_REQUESTS_PER_DECISION = $priorModelMaxHttpRequests }
}

$fixtureHashAfter = if (Test-Path -LiteralPath $savePath -PathType Leaf) { (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash } else { $null }
$fixtureUnchanged = ($fixtureHashBefore -ceq $fixtureHashAfter)
$processStopped = ([bool]$stop.processStopped -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf) -and -not (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue))
$capturePassed = ($captureResult -and $captureResult.Passed -and [double]$captureResult.FrameCoverageRatio -ge 0.9 -and $captureResult.WindowTitle -match 'Bannerlord')
$checkpointSaveRetained = [bool]($CheckpointSaveName -and $checkpointSaveCompleted -and (Test-Path -LiteralPath $checkpointSavePath -PathType Leaf))
$passed = (-not $failure -and $null -ne $liveModelTrace -and $fixtureUnchanged -and $processStopped -and $capturePassed -and (-not $harnessInputLockRequired -or $harnessInputLockConfirmed))

if ($captureResult -and $captureResult.Passed -and $captureResult.VideoRemovedAfterEvidence -and $liveModelTrace.VisualEvidence) {
    $liveModelTrace.VisualEvidence.SourceVideoPath = $null
    $liveModelTrace.VisualEvidence.SourceVideoRemovedAfterKeyframes = $true
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
    CheckpointSaveName = if ($CheckpointSaveName) { $CheckpointSaveName } else { $null }
    CheckpointSavePath = if ($checkpointSaveRetained) { $checkpointSavePath } else { $null }
    CheckpointSaveHash = if ($checkpointSaveRetained) { $checkpointSaveHash } else { $null }
    CheckpointSaveRetained = $checkpointSaveRetained
    CheckpointSaveFailure = $checkpointSaveFailure
    CheckpointSaveStateDisposition = $checkpointSaveStateDisposition
    CheckpointStateContract = $checkpointStateContract
    CampaignInstanceId = $campaignInstanceId
    ProcessId = if ($start -and $start.session) { $start.session.processId } else { $null }
    HarnessInputOwnershipRequired = $harnessInputLockRequired
    HarnessInputOwnershipConfirmed = $harnessInputLockConfirmed
    HostReadyMessages = @($hostReadyMessages)
    CaptureRecoveryProof = $captureRecoveryProof
    Capture = $captureResult
    BattleTargetPreflight = $battleTargetPreflight
    Trace = $liveModelTrace
}
$json = $result | ConvertTo-Json -Depth 28
if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
    Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'LiveModelLoopResult.json') -Value $json -Encoding UTF8
}
$json
if (-not $passed) { exit 1 }
