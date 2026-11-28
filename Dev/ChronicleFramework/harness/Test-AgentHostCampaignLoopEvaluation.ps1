#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(1,3)][int]$Runs = 1,
    [ValidateRange(5,30)][int]$FrameRate = 10,
    [string]$CleanupPreparedSaveName,
    [switch]$VillageToolsQuest,
    [switch]$EstablishYourClanGoalPlanner,
    [switch]$EstablishYourClanAutonomyLoop,
    [switch]$CaptivityRecoveryFromExisting,
    [switch]$EstablishClanGoldSaleFromStoryMode,
    [string]$PlannerSourceSaveName = 'save002',
    [switch]$BattleSimulationLoop,
    [switch]$BattleAndCaptivityLoop,
    [string]$BattleSourceSaveName = 'AgentBridgeLifecycle',
    [switch]$FixtureOpponent
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
. (Join-Path $PSScriptRoot 'Get-FreeLLMAPIProfile.ps1')
if (@($VillageToolsQuest, $EstablishYourClanGoalPlanner, $EstablishYourClanAutonomyLoop, $CaptivityRecoveryFromExisting, $EstablishClanGoldSaleFromStoryMode, $BattleSimulationLoop, $BattleAndCaptivityLoop | Where-Object { $_ }).Count -gt 1) { throw 'Select only one Agent Host Campaign evaluation slice per run.' }
$liveTest = Join-Path $PSScriptRoot 'Test-AgentLiveModelLoop.ps1'
$outerTemp = $env:CHRONICLE_HARNESS_TEMP
if ([string]::IsNullOrWhiteSpace($CleanupPreparedSaveName)) {
    if (-not $outerTemp -or -not (Test-Path -LiteralPath $outerTemp -PathType Container)) { throw 'Agent Host Campaign loop evaluation requires an active Run-Harness TestResults temp directory.' }
    $evaluationRoot = Split-Path -Parent $outerTemp
}
else { $evaluationRoot = $null }
$documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documentsPath)) { throw 'Windows Documents directory could not be resolved for Agent Host cleanup checks.' }
$protocolRoot = Join-Path $documentsPath 'Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent'
$saveDirectory = Join-Path $documentsPath 'Mount and Blade II Bannerlord\Game Saves'
$sessionPath = Join-Path $protocolRoot 'session.json'
$results = [System.Collections.Generic.List[object]]::new()

function Initialize-ChronicleCampaignLoopProviderProfile {
    $baseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'Process')
    if ([string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', 'User') }
    $modelId = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
    if ([string]::IsNullOrWhiteSpace($modelId)) { $modelId = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'User') }
    $protocol = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'Process')
    if ([string]::IsNullOrWhiteSpace($protocol)) { $protocol = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'User') }
    if ([string]::IsNullOrWhiteSpace($protocol)) { $protocol = 'openai-compatible' }

    if ([string]::IsNullOrWhiteSpace($baseUrl) -or [string]::IsNullOrWhiteSpace($modelId)) {
        return Initialize-FreeLLMAPIProfile
    }
    $endpoint = $null
    if ($protocol -ne 'openai-compatible' -or
        -not [Uri]::TryCreate($baseUrl, [UriKind]::Absolute, [ref]$endpoint) -or
        $endpoint.Scheme -notin @('http','https') -or ($endpoint.Scheme -eq 'http' -and -not $endpoint.IsLoopback) -or
        -not [string]::IsNullOrWhiteSpace($endpoint.UserInfo) -or -not [string]::IsNullOrWhiteSpace($endpoint.Query) -or
        -not [string]::IsNullOrWhiteSpace($endpoint.Fragment)) {
        throw 'Configured provider must be an OpenAI-compatible HTTPS endpoint (HTTP is allowed only on loopback), without credentials, query, or fragment.'
    }
    if ($endpoint.IsLoopback -and $endpoint.Port -eq 31415 -and $endpoint.AbsolutePath.TrimEnd('/') -eq '/v1') {
        return Initialize-FreeLLMAPIProfile
    }
    $credential = Get-ChronicleProviderCredential -Endpoint $endpoint
    $apiKey = [string]$credential.Value
    if (-not $endpoint.IsLoopback -and [string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'The configured remote OpenAI-compatible provider requires a user/process API key; no key was printed or written to the provider profile.'
    }
    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_BASE_URL', $baseUrl.TrimEnd('/'), 'Process')
    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_MODEL', $modelId.Trim(), 'Process')
    [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_PROTOCOL', 'openai-compatible', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) { [Environment]::SetEnvironmentVariable('CHRONICLE_LLM_API_KEY', $apiKey, 'Process') }
    $apiKey = $null
    [pscustomobject]@{ BaseUrl = $baseUrl.TrimEnd('/'); RequestedModelId = $modelId.Trim(); ProviderSource = 'configured-openai-compatible-provider' }
}

if (-not [string]::IsNullOrWhiteSpace($CleanupPreparedSaveName)) {
    if (-not ($CleanupPreparedSaveName.StartsWith('ChronicleW7K-', [StringComparison]::Ordinal) -or $CleanupPreparedSaveName.StartsWith('ChronicleW7L-', [StringComparison]::Ordinal) -or $CleanupPreparedSaveName.StartsWith('ChronicleW7N-', [StringComparison]::Ordinal) -or $CleanupPreparedSaveName.StartsWith('ChronicleW7O-', [StringComparison]::Ordinal) -or $CleanupPreparedSaveName.StartsWith('ChronicleW7P-', [StringComparison]::Ordinal))) { throw 'Cleanup-only mode accepts only Harness-owned ChronicleW7K/W7L/W7N/W7O/W7P prepared save names.' }
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Refusing prepared-save cleanup while a Bannerlord process is running.' }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing prepared-save cleanup while a Chronicle Agent CLI session is active.' }
    $saveDirectory = Join-Path $documentsPath 'Mount and Blade II Bannerlord\Game Saves'
    $saveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $preparedSavePath = [IO.Path]::GetFullPath((Join-Path $saveRoot ($CleanupPreparedSaveName + '.sav')))
    $preparedBaseName = [IO.Path]::GetFileNameWithoutExtension($preparedSavePath)
    if (-not $preparedSavePath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase) -or -not ($preparedBaseName.StartsWith('ChronicleW7K-', [StringComparison]::Ordinal) -or $preparedBaseName.StartsWith('ChronicleW7L-', [StringComparison]::Ordinal) -or $preparedBaseName.StartsWith('ChronicleW7N-', [StringComparison]::Ordinal) -or $preparedBaseName.StartsWith('ChronicleW7O-', [StringComparison]::Ordinal) -or $preparedBaseName.StartsWith('ChronicleW7P-', [StringComparison]::Ordinal))) { throw 'Prepared save path escaped the Harness-owned ChronicleW7K/W7L/W7N/W7O/W7P Game Saves boundary.' }
    $removed = -not (Test-Path -LiteralPath $preparedSavePath -PathType Leaf)
    if (-not $removed) {
        [IO.File]::Delete($preparedSavePath)
        $removed = -not (Test-Path -LiteralPath $preparedSavePath -PathType Leaf)
    }
    if (-not $removed) { throw 'Harness-owned prepared save still exists after cleanup.' }
    [pscustomobject]@{ CleanupOnly = $true; PreparedSaveName = $CleanupPreparedSaveName; Removed = $true; BannerlordProcessCount = 0; AgentSessionPresent = $false } | ConvertTo-Json -Compress
    exit 0
}

if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) {
    if ($BattleSourceSaveName -notmatch '^[A-Za-z0-9_-]{1,48}$' -or $BattleSourceSaveName.EndsWith('.sav', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Battle evaluation source must be one Game Saves basename without a path or extension; no Host or model was started.'
    }
}
if (($EstablishYourClanGoalPlanner -or $EstablishYourClanAutonomyLoop -or $CaptivityRecoveryFromExisting -or $EstablishClanGoldSaleFromStoryMode) -and $PlannerSourceSaveName -notmatch '^[A-Za-z0-9_-]{1,48}$') { throw 'StoryMode source must be one Game Saves basename; no model or game process was started.' }

if (Test-Path -LiteralPath $sessionPath -PathType Leaf) {
    $staleSession = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $staleSaveName = [string]$staleSession.saveName
    $stalePid = [int]$staleSession.processId
    if (-not ($staleSaveName.StartsWith('ChronicleW7K-', [StringComparison]::Ordinal) -or $staleSaveName.StartsWith('ChronicleW7L-', [StringComparison]::Ordinal) -or $staleSaveName.StartsWith('ChronicleW7N-', [StringComparison]::Ordinal) -or $staleSaveName.StartsWith('ChronicleW7O-', [StringComparison]::Ordinal) -or $staleSaveName.StartsWith('ChronicleW7P-', [StringComparison]::Ordinal))) {
        throw 'A stale CLI session exists, but its save name is not a Harness-owned ChronicleW7K/W7L/W7N/W7O/W7P fixture; preserving it.'
    }
    if (@(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -gt 0 -or (Get-Process -Id $stalePid -ErrorAction SilentlyContinue)) {
        throw 'A ChronicleW7K session still has a live Bannerlord/session process; refusing automatic recovery.'
    }

    $cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
    $stopOutput = ''
    try { $stopOutput = & $HarnessPowerShell -NoProfile -File $cli stop -AsJson 2>&1 | Out-String }
    catch { $stopOutput = $_.Exception.Message }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'The stale CLI session did not clear through the Agent CLI recovery path.' }
    $cleanupOutput = & $HarnessPowerShell -NoProfile -File $PSCommandPath -CleanupPreparedSaveName $staleSaveName 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "The stale ChronicleW7K fixture save did not clear through bounded cleanup: $cleanupOutput" }
    if ($outerTemp -and (Test-Path -LiteralPath $outerTemp -PathType Container)) {
        [ordered]@{
            RecoveredUtc = [DateTime]::UtcNow.ToString('O')
            ProcessId = $stalePid
            ProcessWasRunning = $false
            SaveName = $staleSaveName
            AgentCliStopOutput = $stopOutput.Trim()
            EngineConfigBackupRemains = Test-Path -LiteralPath (Join-Path $protocolRoot 'engine_config.chronicle-backup')
            CleanupReceipt = ($cleanupOutput | ConvertFrom-Json)
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outerTemp 'AgentHostStaleFixtureRecovery.json') -Encoding UTF8
    }
}

for ($runIndex = 1; $runIndex -le $Runs; $runIndex++) {
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw "Agent Host Campaign run $runIndex found a Bannerlord process left by a previous run." }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw "Agent Host Campaign run $runIndex found a stale CLI session; the fixture must be stopped before testing Host." }

    $runDirectory = Join-Path $evaluationRoot ('AgentHostCampaignRun-{0:D2}' -f $runIndex)
    $runTemp = Join-Path $runDirectory 'Temp'
    New-Item -ItemType Directory -Path $runTemp -Force | Out-Null
    $priorHarnessTemp = $env:CHRONICLE_HARNESS_TEMP
    $priorTemp = $env:TEMP
    $priorTmp = $env:TMP
    $priorProviderProfilePath = $env:CHRONICLE_AGENT_PROFILE_PATH
    $providerEnvironmentNames = @('CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL','CHRONICLE_LLM_PROTOCOL','CHRONICLE_LLM_API_KEY')
    $priorProviderEnvironment = @{}
    foreach ($name in $providerEnvironmentNames) { $priorProviderEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    $env:CHRONICLE_HARNESS_TEMP = $runTemp
    $env:TEMP = $runTemp
    $env:TMP = $runTemp

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $childOutput = ''
    $childExitCode = 1
    $liveResult = $null
    $fixturePreparation = $null
    $preparedSaveName = ''
    $preparedSaveRemoved = $null
    $battleFixtureSaveName = ''
    $battleSourceSavePath = ''
    $battleSourceHashBefore = $null
    $battleSourceHashAfter = $null
    $battleFixtureRemoved = $null
    $plannerSourceSavePath = ''
    $plannerSourceHashBefore = $null
    $plannerSourceHashAfter = $null
    $plannerFixtureSaveName = ''
    $plannerFixtureRemoved = $null
    $saleVerification = $null
    $failure = $null
    try {
        $providerProfile = Initialize-ChronicleCampaignLoopProviderProfile
        $providerBaseUrl = [string]$providerProfile.BaseUrl
        $providerModelId = [string]$providerProfile.RequestedModelId

        $mcmFixtureDirectory = Join-Path $runTemp 'MCM\Global\ChronicleFramework'
        New-Item -ItemType Directory -Path $mcmFixtureDirectory -Force | Out-Null
        $profilePath = Join-Path $mcmFixtureDirectory 'ChronicleAgentSettings.json'
        [ordered]@{ ProviderBaseUrl = $providerBaseUrl; ModelId = $providerModelId; OutputMode = 'auto' } | ConvertTo-Json -Compress | Set-Content -LiteralPath $profilePath -Encoding UTF8
        $env:CHRONICLE_AGENT_PROFILE_PATH = $profilePath
        if ($VillageToolsQuest) {
            $prepOutput = & $HarnessPowerShell -NoProfile -File (Join-Path $PSScriptRoot 'Test-AgentVillageToolsQuestFixturePreparation.ps1') -SourceSaveName 'AgentBridgeLifecycle' -MaxVillages 4 2>&1 | Out-String
            $prepExitCode = $LASTEXITCODE
            $prepResultPath = Join-Path $runTemp 'VillageToolsQuestFixturePreparation.json'
            if (Test-Path -LiteralPath $prepResultPath -PathType Leaf) {
                try { $fixturePreparation = Get-Content -LiteralPath $prepResultPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $failure = 'Native quest fixture preparation receipt was not valid JSON.' }
            }
            if ($prepExitCode -ne 0 -or -not $fixturePreparation -or -not [bool]$fixturePreparation.Prepared) {
                if (-not $failure) { $failure = if ($fixturePreparation -and $fixturePreparation.Failure) { [string]$fixturePreparation.Failure } else { "No natural visible village tools marker was prepared (exit=$prepExitCode)." } }
                throw $failure
            }
            $preparedSaveName = [string]$fixturePreparation.PreparedSaveName
            $childOutput = & $HarnessPowerShell -NoProfile -File $liveTest -LoadSaveName $preparedSaveName -VillageToolsQuestLoop -AgentHostRuntime -FrameRate $FrameRate 2>&1 | Out-String
        }
        elseif ($EstablishYourClanGoalPlanner -or $EstablishYourClanAutonomyLoop -or $CaptivityRecoveryFromExisting -or $EstablishClanGoldSaleFromStoryMode) {
            . (Join-Path $PSScriptRoot 'Agent-SaveMetadata.ps1')
            $saveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $plannerSourceSavePath = [IO.Path]::GetFullPath((Join-Path $saveDirectory ($PlannerSourceSaveName + '.sav')))
            if (-not $plannerSourceSavePath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $plannerSourceSavePath -PathType Leaf)) { throw 'StoryMode planner source save is absent or escaped Game Saves; no copy, Host or model was started.' }
            $plannerSourceModules = @(Get-AgentSaveModuleIds -SavePath $plannerSourceSavePath)
            $requiredPlannerModules = @('Native','SandBoxCore','Sandbox','StoryMode')
            $allowedPlannerModules = @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen','Native','SandBoxCore','CustomBattle','Sandbox','StoryMode','BirthAndDeath','ChronicleFramework')
            $missingPlannerModules = @($requiredPlannerModules | Where-Object { $_ -notin $plannerSourceModules })
            $unexpectedPlannerModules = @($plannerSourceModules | Where-Object { $_ -notin $allowedPlannerModules })
            if ($missingPlannerModules.Count -gt 0 -or $unexpectedPlannerModules.Count -gt 0) { throw 'StoryMode planner source has a missing required Native/StoryMode module or an unsupported third-party module; source was not loaded.' }
            $plannerSourceHashBefore = (Get-FileHash -LiteralPath $plannerSourceSavePath -Algorithm SHA256).Hash
            $plannerFixturePrefix = if ($EstablishClanGoldSaleFromStoryMode -or $EstablishYourClanAutonomyLoop) { 'ChronicleW7P-' } elseif ($CaptivityRecoveryFromExisting) { 'ChronicleW7O-' } else { 'ChronicleW7N-' }
            $plannerFixtureSaveName = $plannerFixturePrefix + [Guid]::NewGuid().ToString('N').Substring(0,16)
            $plannerFixtureSavePath = [IO.Path]::GetFullPath((Join-Path $saveDirectory ($plannerFixtureSaveName + '.sav')))
            if (-not $plannerFixtureSavePath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $plannerFixtureSavePath)) { throw 'Unique W7-N disposable StoryMode save path was not safe/available.' }
            [IO.File]::Copy($plannerSourceSavePath, $plannerFixtureSavePath, $false)
            $plannerCloneHash = (Get-FileHash -LiteralPath $plannerFixtureSavePath -Algorithm SHA256).Hash
            if ($plannerCloneHash -cne $plannerSourceHashBefore) { throw 'The W7-N disposable save copy does not match its read-only source hash.' }
            [ordered]@{ SourceSaveName = $PlannerSourceSaveName; SourceSha256Before = $plannerSourceHashBefore; SourceModuleIds = $plannerSourceModules; RuntimeLoadModuleAugment = @('ChronicleFramework'); DisposableCloneName = $plannerFixtureSaveName; DisposableClonePrefix = $plannerFixturePrefix; DisposableCloneSha256 = $plannerCloneHash; IsByteForByteCopy = $true; NoGameWorldStateInjected = (-not $FixtureOpponent); InjectedWorldState = if ($FixtureOpponent) { 'one disposable hostile looter party (visual-opponent-fixture) so the Renown route has an opportunity; save bytes are copied unchanged' } else { $null } } |
                ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runTemp 'EstablishYourClanSourceFixture.json') -Encoding UTF8
            $storyModeLoopSwitch = if ($EstablishClanGoldSaleFromStoryMode) { '-EstablishClanGoldSaleLoop' } elseif ($CaptivityRecoveryFromExisting) { '-CaptivityRecoveryLoop' } elseif ($EstablishYourClanAutonomyLoop) { '-EstablishYourClanAutonomyLoop' } else { '-EstablishYourClanGoalPlanner' }
            # The opponent fixture is a disposable-save harness privilege, not game progress: it only guarantees
            # that one hostile party is visible so a Renown route has an opportunity. The fixture receipt states it.
            $childFixtureSwitch = @()
            if ($FixtureOpponent) { $childFixtureSwitch = @('-FixtureOpponent') }
            $childOutput = & $HarnessPowerShell -NoProfile -File $liveTest -LoadSaveName $plannerFixtureSaveName $storyModeLoopSwitch -AgentHostRuntime -FrameRate $FrameRate @childFixtureSwitch 2>&1 | Out-String
        }
        elseif ($BattleSimulationLoop -or $BattleAndCaptivityLoop) {
            $battleSaveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $battleSourceSavePath = [IO.Path]::GetFullPath((Join-Path $saveDirectory ($BattleSourceSaveName + '.sav')))
            if (-not $battleSourceSavePath.StartsWith($battleSaveRoot, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $battleSourceSavePath -PathType Leaf)) { throw 'Battle source save is absent or escaped Game Saves; no copy, Host or model was started.' }
            . (Join-Path $PSScriptRoot 'Agent-SaveMetadata.ps1')
            $sourceModules = @(Get-AgentSaveModuleIds -SavePath $battleSourceSavePath)
            $requiredModules = @('Native','SandBoxCore','Sandbox','BirthAndDeath','ChronicleFramework')
            $allowedModules = @('Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen','Native','SandBoxCore','CustomBattle','Sandbox','StoryMode','BirthAndDeath','ChronicleFramework')
            $sourceModuleSet = @($sourceModules | ForEach-Object { $_.ToLowerInvariant() })
            $missingRequiredModules = @($requiredModules | Where-Object { $_.ToLowerInvariant() -notin $sourceModuleSet })
            $unexpectedModules = @($sourceModules | Where-Object { $_ -notin $allowedModules })
            if ($missingRequiredModules.Count -gt 0 -or $unexpectedModules.Count -gt 0) { throw 'Battle source save module set is outside the supported Native Chronicle test profile; source was not loaded.' }

            $battleSourceHashBefore = (Get-FileHash -LiteralPath $battleSourceSavePath -Algorithm SHA256).Hash
            $battleFixtureSaveName = 'ChronicleW7L-' + [Guid]::NewGuid().ToString('N').Substring(0,16)
            $battleFixtureSavePath = [IO.Path]::GetFullPath((Join-Path $saveDirectory ($battleFixtureSaveName + '.sav')))
            if (-not $battleFixtureSavePath.StartsWith($battleSaveRoot, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $battleFixtureSavePath)) { throw 'Unique W7-L disposable save path was not safe/available.' }
            [IO.File]::Copy($battleSourceSavePath, $battleFixtureSavePath, $false)
            $battleCloneHash = (Get-FileHash -LiteralPath $battleFixtureSavePath -Algorithm SHA256).Hash
            if ($battleCloneHash -cne $battleSourceHashBefore) { throw 'The W7-L disposable save copy does not match its read-only source hash.' }
            [ordered]@{ SourceSaveName = $BattleSourceSaveName; SourceSha256Before = $battleSourceHashBefore; SourceModuleIds = $sourceModules; DisposableCloneName = $battleFixtureSaveName; DisposableCloneSha256 = $battleCloneHash; IsByteForByteCopy = $true; NoGameWorldStateInjected = $true } |
                ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runTemp 'BattleSourceFixture.json') -Encoding UTF8
            $battleLoopSwitch = if ($BattleAndCaptivityLoop) { '-BattleAndCaptivityLoop' } else { '-BattleSimulationLoop' }
            $childOutput = & $HarnessPowerShell -NoProfile -File $liveTest -LoadSaveName $battleFixtureSaveName $battleLoopSwitch -AgentHostRuntime -FrameRate $FrameRate 2>&1 | Out-String
        }
        else {
            $childOutput = & $HarnessPowerShell -NoProfile -File $liveTest -ArrivalLoop -AgentHostRuntime -FrameRate $FrameRate 2>&1 | Out-String
        }
        $childExitCode = $LASTEXITCODE
        $resultPath = Join-Path $runTemp 'LiveModelLoopResult.json'
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            try { $liveResult = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json }
            catch { $failure = 'Host live-loop receipt was not parseable JSON.' }
        }
        if ($childExitCode -ne 0 -and -not $failure) {
            $failure = if ($liveResult -and $liveResult.Failure) { [string]$liveResult.Failure } else { "Agent Host live-loop child exited $childExitCode without an acceptance result." }
        }
        if (-not $liveResult -and -not $failure) { $failure = 'Host live-loop did not produce LiveModelLoopResult.json.' }
    }
    catch { $failure = $_.Exception.Message }
    finally {
        $watch.Stop()
        if ($VillageToolsQuest -and $preparedSaveName -and -not (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)) {
            $saveDirectory = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)) 'Mount and Blade II Bannerlord\Game Saves'
            $preparedSavePath = [IO.Path]::GetFullPath((Join-Path $saveDirectory ($preparedSaveName + '.sav')))
            $expectedSaveDirectory = [IO.Path]::GetFullPath($saveDirectory) + [IO.Path]::DirectorySeparatorChar
            if ($preparedSaveName.StartsWith('ChronicleW7K-', [StringComparison]::Ordinal) -and $preparedSavePath.StartsWith($expectedSaveDirectory, [StringComparison]::OrdinalIgnoreCase)) {
                if (Test-Path -LiteralPath $preparedSavePath -PathType Leaf) { [IO.File]::Delete($preparedSavePath) }
                $preparedSaveRemoved = -not (Test-Path -LiteralPath $preparedSavePath -PathType Leaf)
            }
        }
        if (($BattleSimulationLoop -or $BattleAndCaptivityLoop) -and $battleFixtureSaveName) {
            $battleRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $battleFixturePath = [IO.Path]::GetFullPath((Join-Path $saveDirectory ($battleFixtureSaveName + '.sav')))
            if ((Test-Path -LiteralPath $battleFixturePath -PathType Leaf) -and $battleFixtureSaveName.StartsWith('ChronicleW7L-', [StringComparison]::Ordinal) -and
                $battleFixturePath.StartsWith($battleRoot, [StringComparison]::OrdinalIgnoreCase) -and
                -not (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
                [IO.File]::Delete($battleFixturePath)
            }
            $battleFixtureRemoved = -not (Test-Path -LiteralPath $battleFixturePath -PathType Leaf)
            if (Test-Path -LiteralPath $battleSourceSavePath -PathType Leaf) { $battleSourceHashAfter = (Get-FileHash -LiteralPath $battleSourceSavePath -Algorithm SHA256).Hash }
        }
        if (($EstablishYourClanGoalPlanner -or $EstablishYourClanAutonomyLoop -or $CaptivityRecoveryFromExisting -or $EstablishClanGoldSaleFromStoryMode) -and $plannerFixtureSaveName) {
            $plannerRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $plannerFixturePath = [IO.Path]::GetFullPath((Join-Path $saveDirectory ($plannerFixtureSaveName + '.sav')))
            if ((Test-Path -LiteralPath $plannerFixturePath -PathType Leaf) -and
                ($plannerFixtureSaveName.StartsWith('ChronicleW7N-', [StringComparison]::Ordinal) -or $plannerFixtureSaveName.StartsWith('ChronicleW7O-', [StringComparison]::Ordinal) -or $plannerFixtureSaveName.StartsWith('ChronicleW7P-', [StringComparison]::Ordinal)) -and
                $plannerFixturePath.StartsWith($plannerRoot, [StringComparison]::OrdinalIgnoreCase) -and
                -not (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
                [IO.File]::Delete($plannerFixturePath)
            }
            $plannerFixtureRemoved = -not (Test-Path -LiteralPath $plannerFixturePath -PathType Leaf)
            if (Test-Path -LiteralPath $plannerSourceSavePath -PathType Leaf) { $plannerSourceHashAfter = (Get-FileHash -LiteralPath $plannerSourceSavePath -Algorithm SHA256).Hash }
        }
        $env:CHRONICLE_HARNESS_TEMP = $priorHarnessTemp
        $env:TEMP = $priorTemp
        $env:TMP = $priorTmp
        if ($null -eq $priorProviderProfilePath) { Remove-Item Env:CHRONICLE_AGENT_PROFILE_PATH -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_AGENT_PROFILE_PATH = $priorProviderProfilePath }
        foreach ($name in $providerEnvironmentNames) { [Environment]::SetEnvironmentVariable($name, $priorProviderEnvironment[$name], 'Process') }
    }

    $trace = if ($liveResult) { $liveResult.Trace } else { $null }
    $modelSteps = if ($trace -and $trace.Trace) { @($trace.Trace) } else { @() }
    $nativeActions = @($modelSteps | Where-Object { $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' })
    $observeAgainSteps = @($modelSteps | Where-Object { $_.control.kind -eq 'bounded-observe-again' -and -not $_.actionExecuted })
    $noGameProcesses = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -eq 0
    $noSessionFile = -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)
    if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) {
        $battleOutcome = if ($trace) { $trace.BattleOutcome } else { $null }
        $battleTargetId = if ($battleOutcome) { [string]$battleOutcome.TargetPartyId } else { '' }
        $clockActions = if ($trace) { @($trace.NativeClockActions | Where-Object { [string]$_ -in @('advance','pause','resume','fastForward') }) } else { @() }
        $battleActionSequence = @($nativeActions | ForEach-Object { [string]$_.actionReceipt.action })
        $dialogueChoiceSteps = @($modelSteps | Where-Object { $_.actionExecuted -and [string]$_.decision.action -ceq 'dialogueSelect' })
        $dialogueChoiceAudit = @($dialogueChoiceSteps | ForEach-Object {
            $optionId = [string]$_.decision.arguments.OptionId
            $allowedIds = @($_.allowedActions | Where-Object { [string]$_.action -ceq 'dialogueSelect' } | ForEach-Object { @($_.argumentValues.OptionId) })
            $currentIds = @($_.observationBefore.state.context.conversation.options | Where-Object { [bool]$_.clickable } | ForEach-Object { [string]$_.id })
            [pscustomobject]@{
                optionId = $optionId
                currentlyCatalogued = $allowedIds -contains $optionId
                currentlyClickable = $currentIds -contains $optionId
                visibleOptions = $currentIds
            }
        })
        $dialogueChoiceIds = @($dialogueChoiceAudit | ForEach-Object { [string]$_.optionId })
        $dialogueChoicesConform = @($dialogueChoiceAudit | Where-Object { -not $_.currentlyCatalogued -or -not $_.currentlyClickable }).Count -eq 0
        $meetingSteps = @($modelSteps | Where-Object { [string]$_.observationBefore.state.context.menuId -ceq 'encounter_meeting' })
        $requiredMeetingChoicesSatisfied = $true
        foreach ($meetingStep in $meetingSteps) {
            $visibleIds = @($meetingStep.observationBefore.state.context.conversation.options | Where-Object { [bool]$_.clickable } | ForEach-Object { [string]$_.id })
            $expectedMeetingChoice = if ($visibleIds -contains 'bandit_start_defender_1') { 'bandit_start_defender_1' }
                elseif ($visibleIds -contains 'common_encounter_ultimatum') { 'common_encounter_ultimatum' }
                else { $null }
            if ($expectedMeetingChoice -and $dialogueChoiceIds -notcontains $expectedMeetingChoice) { $requiredMeetingChoicesSatisfied = $false }
        }
        $declinedVisibleSurrender = @($modelSteps | Where-Object {
            @($_.observationBefore.state.context.conversation.options | Where-Object { [string]$_.id -ceq 'common_bandit_surrender_declined' -and [bool]$_.clickable }).Count -gt 0
        }).Count -gt 0
        $surrenderDeclinedWhenOffered = -not $declinedVisibleSurrender -or $dialogueChoiceIds -contains 'common_bandit_surrender_declined'
        if ($battleOutcome) {
            $battleOutcome | Add-Member -NotePropertyName NativeDialogueChoiceIds -NotePropertyValue $dialogueChoiceIds -Force
            $battleOutcome | Add-Member -NotePropertyName NativeDialogueChoiceAudit -NotePropertyValue $dialogueChoiceAudit -Force
        }
        $providerRoutes = if ($trace -and $trace.ProviderRouteHistory) { @($trace.ProviderRouteHistory) } else { @() }
        $renownBeforeFinite = ($null -ne $trace.BattleRenownBefore -and -not [double]::IsNaN([double]$trace.BattleRenownBefore) -and -not [double]::IsInfinity([double]$trace.BattleRenownBefore))
        $renownAfterFinite = ($null -ne $trace.BattleRenownAfter -and -not [double]::IsNaN([double]$trace.BattleRenownAfter) -and -not [double]::IsInfinity([double]$trace.BattleRenownAfter))
        # Source cleanliness is checked at the live test boundary; this evaluator
        # also requires the real provider route and a freshly observed target.
        $playerOutcomeVerified = if ($BattleAndCaptivityLoop) {
            [bool]$battleOutcome.CaptivityRecoveryRequested -and [bool]$battleOutcome.CaptivityObserved -and
            [bool]$battleOutcome.CaptivityRecoveryVerified -and [string]$battleOutcome.PlayerOutcome -ceq 'captured-then-recovered' -and
            -not [bool]$battleOutcome.PlayerCaptiveAtMapReturn -and [bool]$battleOutcome.FreeMapReturned -and [int]$battleOutcome.MainPartyMembersAtReturn -gt 0
        }
        else { [string]$battleOutcome.PlayerOutcome -in @('captured','retreated','resolved-native-battle') }
        $battleEvidenceVerified = (
            $childExitCode -eq 0 -and $liveResult -and [bool]$liveResult.Passed -and
            [bool]$trace.BattleSimulationVerified -and [bool]$trace.BattleReturnToMapVerified -and
            $battleTargetId.Length -gt 0 -and $renownBeforeFinite -and $renownAfterFinite -and $clockActions.Count -eq 0 -and
            $battleActionSequence.Contains('mapPartyTargets') -and $battleActionSequence.Contains('menuSelect') -and
            $battleActionSequence.Contains('battleFinish') -and
            $dialogueChoicesConform -and $requiredMeetingChoicesSatisfied -and $surrenderDeclinedWhenOffered -and
            [string]$battleOutcome.SendTroopsOption -ceq 'str_order_attack' -and [string]$battleOutcome.SimulationState -ne 'unknown' -and
            $playerOutcomeVerified -and
            [string]$battleOutcome.BattleFinishReceipt.status -ceq 'completed' -and
            ([int]$battleOutcome.PartyLootScreenCount -eq 0 -or $battleActionSequence.Contains('partyScreenDone')) -and
            ([int]$battleOutcome.InventoryLootScreenCount -eq 0 -or $battleActionSequence.Contains('inventoryDone')) -and
            $providerRoutes.Count -gt 0 -and [string]$trace.ModelConfigurationSource -eq 'harness-mcm-profile-fixture' -and
            [bool]$liveResult.FixtureUnchanged -and [bool]$liveResult.ProcessStopped -and
            [bool]$battleSourceHashBefore -and $battleSourceHashBefore -ceq $battleSourceHashAfter -and [bool]$battleFixtureRemoved -and
            [bool]$liveResult.VisualEvidencePassed -and [double]$liveResult.Capture.FrameCoverageRatio -ge 0.9 -and
            [bool]$liveResult.Capture.VideoRemovedAfterEvidence -and
            [bool]$trace.SourceTrackedTreeClean -and [string]$trace.SourceCommit -eq (git.exe -C $PSScriptRoot rev-parse HEAD).Trim() -and
            $noGameProcesses -and $noSessionFile
        )
        $passed = [bool]$battleEvidenceVerified
        if (-not $passed -and -not $failure) { $failure = 'One or more real-model Native battle, target, actual post-battle/captivity outcome, no-clock, visual, source, or cleanup assertions failed.' }
    }
    elseif ($EstablishClanGoldSaleFromStoryMode) {
        $saleVerification = $trace.EstablishClanGoldSaleVerification
        $journalGoldBeforeValue = $saleVerification.objectiveJournalBefore.JournalGoldCurrent
        $journalGoldAfterValue = $saleVerification.objectiveJournalAfter.current
        $journalGoldTargetValue = $saleVerification.objectiveJournalAfter.target
        $journalGoldBefore = if ($null -ne $journalGoldBeforeValue) { [double]$journalGoldBeforeValue } else { [double]::NaN }
        $journalGoldAfter = if ($null -ne $journalGoldAfterValue) { [double]$journalGoldAfterValue } else { [double]::NaN }
        $journalGoldTarget = if ($null -ne $journalGoldTargetValue) { [double]$journalGoldTargetValue } else { [double]::NaN }
        $journalGoldEvidenceComplete = -not [double]::IsNaN($journalGoldBefore) -and -not [double]::IsInfinity($journalGoldBefore) -and
            -not [double]::IsNaN($journalGoldAfter) -and -not [double]::IsInfinity($journalGoldAfter) -and
            -not [double]::IsNaN($journalGoldTarget) -and -not [double]::IsInfinity($journalGoldTarget)
        $saleReceipts = @($nativeActions | Where-Object { [string]$_.actionReceipt.action -eq 'trade' -and [string]$_.actionReceipt.data.direction -ceq 'sell' })
        $tradeOptionsReceipts = @($nativeActions | Where-Object { [string]$_.actionReceipt.action -eq 'tradeOptions' })
        $tradeCommits = @($nativeActions | Where-Object { [string]$_.actionReceipt.action -eq 'tradeConfirm' -and [bool]$_.actionReceipt.data.postconditionPassed })
        $clockActions = @($trace.NativeClockActions | Where-Object { [string]$_ -in @('advance','pause','resume','fastForward') })
        $allowedClockActions = if ([bool]$trace.EstablishClanGoldSaleBaseline.CaptiveAtStart) { @('resume') } else { @() }
        $safeActions = @($nativeActions | Where-Object { [string]$_.actionReceipt.action -in @('mapSettlementTargets','move','menuSelect','tradeOptions','trade','tradeConfirm','tradeCancel','tradeCancelChanges','resume') })
        $passed = (
            $childExitCode -eq 0 -and $liveResult -and [bool]$liveResult.Passed -and
            [bool]$liveResult.FixtureUnchanged -and [bool]$liveResult.ProcessStopped -and
            [string]$trace.ModelConfigurationSource -eq 'harness-mcm-profile-fixture' -and
            [string]$trace.AcceptanceSlice -eq 'Real-model Native StoryMode Gold objective progress through one market sale' -and
            [bool]$trace.EstablishClanGoldSaleVerified -and [bool]$saleVerification.passed -and
            [string]$trace.SourceCommit -eq (git.exe -C $PSScriptRoot rev-parse HEAD).Trim() -and [bool]$trace.SourceTrackedTreeClean -and
            [string]$trace.EstablishClanGoldSaleBaseline.QuestId -ceq 'rebuild_player_clan_storymode_quest' -and
            $journalGoldEvidenceComplete -and $journalGoldAfter -gt $journalGoldBefore -and $journalGoldTarget -eq 2000 -and
            $saleReceipts.Count -eq 1 -and $tradeOptionsReceipts.Count -eq 1 -and $tradeCommits.Count -eq 1 -and
            [string]$saleReceipts[0].decision.arguments.Direction -ceq 'sell' -and
            [string]$saleReceipts[0].decision.arguments.InventorySide -ceq 'PlayerInventory' -and [int]$saleReceipts[0].decision.arguments.Amount -eq 1 -and
            [bool]$saleVerification.nativeTradeTimeChanged -eq $false -and
            -not [bool]$saleVerification.originalQuestCompletionClaimed -and
            (-not [bool]$trace.EstablishClanGoldSaleBaseline.CaptiveAtStart -or [bool]$saleVerification.captivityPreludeVerified) -and
            $clockActions.Count -eq $allowedClockActions.Count -and
            @($clockActions | Where-Object { $_ -notin $allowedClockActions }).Count -eq 0 -and
            $safeActions.Count -eq $nativeActions.Count -and
            [bool]$liveResult.VisualEvidencePassed -and [double]$liveResult.Capture.FrameCoverageRatio -ge 0.9 -and
            [bool]$liveResult.Capture.VideoRemovedAfterEvidence -and $plannerFixtureRemoved -and
            [bool]$plannerSourceHashBefore -and $plannerSourceHashBefore -ceq $plannerSourceHashAfter -and
            $noGameProcesses -and $noSessionFile
        )
        if (-not $passed -and -not $failure) { $failure = 'One or more Native sale offer, exact Gold/inventory delta, Journal progress, no-clock, source integrity, visual or cleanup assertions failed.' }
    }
    elseif ($CaptivityRecoveryFromExisting) {
        $captureActions = @($nativeActions | ForEach-Object { [string]$_.actionReceipt.action })
        $clockActions = @($trace.NativeClockActions)
        $plannerSelection = $trace.CaptivityRecoveryObjectiveSelection
        $passed = (
            $childExitCode -eq 0 -and $liveResult -and [bool]$liveResult.Passed -and
            [bool]$liveResult.FixtureUnchanged -and [bool]$liveResult.ProcessStopped -and
            [string]$trace.ModelConfigurationSource -eq 'harness-mcm-profile-fixture' -and
            [string]$trace.AcceptanceSlice -eq 'Real-model Native recovery from existing StoryMode MainHero captivity followed by objective replanning' -and
            [bool]$trace.CaptivityRecoveryVerified -and
            [string]$trace.CaptivityRecoveryPlannerVerification.initialStoryModeStatus -ceq 'active' -and
            [string]$trace.CaptivityRecoveryPlannerVerification.finalStoryModeStatus -ceq 'active' -and
            [bool]$trace.CaptivityRecoveryPlannerVerification.finalCaptive -eq $false -and
            [string]$trace.CaptivityRecoveryPlannerVerification.nativeActionSequence -match 'resume' -and
            $clockActions -contains 'resume' -and
            @($clockActions | Where-Object { $_ -in @('pause','fastForward','advance') }).Count -eq 0 -and
            $captureActions.Count -gt 0 -and @($captureActions | Where-Object { $_ -in @('mapPartyTargets','pursue','battleSkip','battleFinish','partyTakeAll','inventoryTakeAll') }).Count -eq 0 -and
            $plannerSelection -and [string]$plannerSelection.objectiveId -in @('gold','partySize','renown','companions') -and
            [bool]$trace.CaptivityRecoveryPlannerVerification.goalVerified -eq $false -and
            [bool]$trace.SourceTrackedTreeClean -and [string]$trace.SourceCommit -eq (git.exe -C $PSScriptRoot rev-parse HEAD).Trim() -and
            [bool]$plannerFixtureRemoved -and [bool]$plannerSourceHashBefore -and $plannerSourceHashBefore -ceq $plannerSourceHashAfter -and
            [bool]$liveResult.VisualEvidencePassed -and [double]$liveResult.Capture.FrameCoverageRatio -ge 0.9 -and
            [bool]$liveResult.Capture.VideoRemovedAfterEvidence -and $noGameProcesses -and $noSessionFile
        )
        if (-not $passed -and -not $failure) { $failure = 'One or more Native existing-Captivity recovery, explicit time, objective replan, source integrity, visual or cleanup assertions failed.' }
    }
    elseif ($EstablishYourClanAutonomyLoop) {
        $autonomyVerification = $trace.EstablishYourClanAutonomyVerification
        $autonomyRoutes = @($trace.ProviderRouteHistory)
        $clockActions = @($nativeActions | Where-Object { [string]$_.actionReceipt.action -in @('advance','pause','resume','fastForward') })
        $passed = (
            $childExitCode -eq 0 -and $liveResult -and [bool]$liveResult.Passed -and
            [bool]$trace.EstablishYourClanAutonomyLoopVerified -and [bool]$autonomyVerification.nativeQuestSucceeded -and
            [string]$autonomyVerification.nativeLifecycleStatus -ceq 'completed' -and
            [bool]$autonomyVerification.allFourFinalJournalObjectivesMet -and
            [string]$trace.ModelConfigurationSource -ceq 'harness-mcm-profile-fixture' -and $autonomyRoutes.Count -gt 0 -and
            $clockActions.Count -eq 0 -and [bool]$trace.SourceTrackedTreeClean -and
            [string]$trace.SourceCommit -eq (git.exe -C $PSScriptRoot rev-parse HEAD).Trim() -and
            [bool]$liveResult.FixtureUnchanged -and [bool]$liveResult.ProcessStopped -and
            [bool]$plannerFixtureRemoved -and [bool]$plannerSourceHashBefore -and $plannerSourceHashBefore -ceq $plannerSourceHashAfter -and
            [bool]$liveResult.VisualEvidencePassed -and [double]$liveResult.Capture.FrameCoverageRatio -ge 0.9 -and
            [bool]$liveResult.Capture.VideoRemovedAfterEvidence -and $noGameProcesses -and $noSessionFile
        )
        if (-not $passed -and -not $failure) { $failure = 'The real-model EYC executor run did not verify original Native Quest completion or preserve the source fixture/visual/process cleanup evidence.' }
    }
    elseif ($EstablishYourClanGoalPlanner) {
        $plannerSelection = $trace.EstablishYourClanObjectiveSelection
        $plannerRoutes = @($trace.ProviderRouteHistory)
        $clockActions = @($trace.NativeClockActions)
        $passed = (
            $childExitCode -eq 0 -and $liveResult -and [bool]$liveResult.Passed -and
            [bool]$liveResult.FixtureUnchanged -and [bool]$liveResult.ProcessStopped -and
            [string]$trace.ModelConfigurationSource -eq 'harness-mcm-profile-fixture' -and
            [string]$trace.AcceptanceSlice -eq 'Real-model read-only selection of one unmet original StoryMode Establish Your Clan objective' -and
            [bool]$trace.EstablishYourClanPlannerVerified -and
            -not [bool]$trace.EstablishYourClanGoalVerified -and
            [string]$trace.EstablishYourClanQuestStatusBefore -ceq 'active' -and
            [string]$trace.EstablishYourClanQuestStatusAfter -ceq 'active' -and
            $plannerSelection -and [string]$plannerSelection.objectiveId -in @('gold','partySize','renown','companions') -and
            [bool]$trace.EstablishYourClanTargetConsistency.consistent -and
            $plannerRoutes.Count -ge 2 -and $clockActions.Count -eq 0 -and
            [bool]$plannerFixtureRemoved -and
            [bool]$plannerSourceHashBefore -and $plannerSourceHashBefore -ceq $plannerSourceHashAfter -and
            [bool]$trace.SourceTrackedTreeClean -and [string]$trace.SourceCommit -eq (git.exe -C $PSScriptRoot rev-parse HEAD).Trim() -and
            [bool]$liveResult.VisualEvidencePassed -and [double]$liveResult.Capture.FrameCoverageRatio -ge 0.9 -and
            [bool]$liveResult.Capture.VideoRemovedAfterEvidence -and $noGameProcesses -and $noSessionFile
        )
        if (-not $passed -and -not $failure) { $failure = 'One or more configured-provider objective-selection, active-Quest, read-only world/time preservation, source hash, visual, or cleanup assertions failed.' }
    }
    elseif ($VillageToolsQuest) {
        $requiredActions = @('talkToSettlementHero','dialogueSelect','questDetails','tradeOptions','trade','tradeConfirm','inventoryOpen','heroEquipmentOptions','inventoryCancel')
        $requiredActionsObserved = $true
        foreach ($requiredAction in $requiredActions) {
            if (@($nativeActions | Where-Object { [string]$_.actionReceipt.action -eq $requiredAction }).Count -eq 0) { $requiredActionsObserved = $false; break }
        }
        $talkStep = @($modelSteps | Where-Object { [string]$_.decision.action -eq 'talkToSettlementHero' } | Select-Object -First 1)
        $visibleIssueMarkerVerified = $false
        if ($talkStep.Count -eq 1) {
            $talkHeroId = [string]$talkStep[0].decision.arguments.HeroId
            $observedGiver = @($talkStep[0].observationBefore.state.settlementOverlayCharacters | Where-Object { [string]$_.heroId -ceq $talkHeroId })
            $visibleIssueMarkerVerified = ($observedGiver.Count -eq 1 -and @($observedGiver[0].questMarkers | Where-Object {
                [string]$_.type -eq 'AvailableIssue' -and
                (([string]$_.title + ' ' + [string]$_.hint) -match '(?i)tools?' -or (([string]$_.title + ' ' + [string]$_.hint).Contains(([char]0x5DE5).ToString() + ([char]0x5177).ToString())))
            }).Count -gt 0)
        }
        $tradeCommits = @($nativeActions | Where-Object { [string]$_.actionReceipt.action -eq 'tradeConfirm' -and $_.actionReceipt.data.committed -eq $true })
        $clockActions = @($nativeActions | Where-Object { $_.actionReceipt.action -in @('advance','pause','resume','fastForward') })
        $passed = (
            $childExitCode -eq 0 -and $liveResult -and [bool]$liveResult.Passed -and
            [bool]$liveResult.FixtureUnchanged -and [bool]$liveResult.ProcessStopped -and
            [string]$trace.ModelConfigurationSource -eq 'harness-mcm-profile-fixture' -and
            [string]$trace.AcceptanceSlice -eq 'Real-model Native VillageNeedsTools quest acceptance, delivery and exact inventory delta' -and
            [bool]$trace.VillageToolsQuestVerified -and [bool]$trace.VillageToolsQuestInventoryDeltaVerified -and
            [bool]$trace.ProviderStoppedAfterGoalAction -and [int]$trace.Decisions -le 100 -and
            $visibleIssueMarkerVerified -and $tradeCommits.Count -eq 1 -and [string]$tradeCommits[0].actionReceipt.data.itemId -ceq 'tools' -and
            [bool]$fixturePreparation.Prepared -and [bool]$fixturePreparation.SourceFixtureUnchanged -and [bool]$preparedSaveRemoved -and
            $requiredActionsObserved -and $clockActions.Count -eq 0 -and
            [bool]$trace.SourceTrackedTreeClean -and [string]$trace.SourceCommit -eq (git.exe -C $PSScriptRoot rev-parse HEAD).Trim() -and
            [bool]$liveResult.VisualEvidencePassed -and [double]$liveResult.Capture.FrameCoverageRatio -ge 0.9 -and
            [bool]$liveResult.Capture.VideoRemovedAfterEvidence -and $noGameProcesses -and $noSessionFile
        )
        if (-not $passed -and -not $failure) { $failure = 'One or more real-model Quest, exact Inventory delta, no-clock, visual, source, or cleanup assertions failed.' }
    }
    else {
        $passed = (
            $childExitCode -eq 0 -and $liveResult -and [bool]$liveResult.Passed -and
            [bool]$liveResult.FixtureUnchanged -and [bool]$liveResult.ProcessStopped -and
            [string]$trace.ModelConfigurationSource -eq 'harness-mcm-profile-fixture' -and
            [string]$trace.AcceptanceSlice -eq 'Native movement arrival' -and
            [bool]$trace.ArrivalConfirmed -and [bool]$trace.CampaignDayAdvancedDuringTravel -and
            [bool]$trace.ProviderStoppedAfterGoalAction -and [int]$trace.Decisions -ge 3 -and [int]$trace.Decisions -le 30 -and
            $nativeActions.Count -eq 2 -and @($nativeActions | Where-Object { $_.actionReceipt.action -eq 'mapSettlementTargets' }).Count -eq 1 -and
            @($nativeActions | Where-Object { $_.actionReceipt.action -eq 'move' }).Count -eq 1 -and $observeAgainSteps.Count -gt 0 -and
            [bool]$trace.SourceTrackedTreeClean -and [string]$trace.SourceCommit -eq (git.exe -C $PSScriptRoot rev-parse HEAD).Trim() -and
            [bool]$liveResult.VisualEvidencePassed -and [double]$liveResult.Capture.FrameCoverageRatio -ge 0.9 -and
            [bool]$liveResult.Capture.VideoRemovedAfterEvidence -and $noGameProcesses -and $noSessionFile
        )
        if (-not $passed -and -not $failure) { $failure = 'One or more Native arrival, Host, natural-time, visual, source, or cleanup assertions failed.' }
    }
    $results.Add([ordered]@{
        run = $runIndex
        passed = [bool]$passed
        sourceCommit = if ($trace) { [string]$trace.SourceCommit } else { $null }
        modelId = if ($trace) { [string]$trace.ModelId } else { $null }
        modelConfigurationSource = if ($trace) { [string]$trace.ModelConfigurationSource } else { $null }
        fixturePreparedFromNaturalVisibleIssue = if ($fixturePreparation) { [bool]$fixturePreparation.Prepared } else { $null }
        preparedIssueGiver = if ($fixturePreparation) { $fixturePreparation.VisibleMarker } else { $null }
        battleOutcome = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { $battleOutcome } else { $null }
        storyModePlannerSourceSave = if ($EstablishYourClanGoalPlanner) { $PlannerSourceSaveName } else { $null }
        storyModePlannerSourceHashBefore = if ($EstablishYourClanGoalPlanner) { $plannerSourceHashBefore } else { $null }
        storyModePlannerSourceHashAfter = if ($EstablishYourClanGoalPlanner) { $plannerSourceHashAfter } else { $null }
        storyModePlannerFixtureRemoved = if ($EstablishYourClanGoalPlanner) { $plannerFixtureRemoved } else { $null }
        storyModeObjectiveSelection = if ($EstablishYourClanGoalPlanner -and $trace) { $trace.EstablishYourClanObjectiveSelection } else { $null }
        storyModeObjectiveTargetConsistency = if ($EstablishYourClanGoalPlanner -and $trace) { $trace.EstablishYourClanTargetConsistency } else { $null }
        storyModeAutonomySourceSave = if ($EstablishYourClanAutonomyLoop) { $PlannerSourceSaveName } else { $null }
        storyModeAutonomySourceHashBefore = if ($EstablishYourClanAutonomyLoop) { $plannerSourceHashBefore } else { $null }
        storyModeAutonomySourceHashAfter = if ($EstablishYourClanAutonomyLoop) { $plannerSourceHashAfter } else { $null }
        storyModeAutonomyFixtureRemoved = if ($EstablishYourClanAutonomyLoop) { $plannerFixtureRemoved } else { $null }
        storyModeAutonomyVerified = if ($EstablishYourClanAutonomyLoop -and $trace) { [bool]$trace.EstablishYourClanAutonomyLoopVerified } else { $null }
        storyModeAutonomyEvidence = if ($EstablishYourClanAutonomyLoop) { $trace.EstablishYourClanAutonomyVerification } else { $null }
        storyModeCaptivitySourceSave = if ($CaptivityRecoveryFromExisting) { $PlannerSourceSaveName } else { $null }
        storyModeCaptivitySourceHashBefore = if ($CaptivityRecoveryFromExisting) { $plannerSourceHashBefore } else { $null }
        storyModeCaptivitySourceHashAfter = if ($CaptivityRecoveryFromExisting) { $plannerSourceHashAfter } else { $null }
        storyModeCaptivityFixtureRemoved = if ($CaptivityRecoveryFromExisting) { $plannerFixtureRemoved } else { $null }
        storyModeCaptivityObjectiveSelection = if ($CaptivityRecoveryFromExisting -and $trace) { $trace.CaptivityRecoveryObjectiveSelection } else { $null }
        storyModeCaptivityTimeActions = if ($CaptivityRecoveryFromExisting -and $trace) { @($trace.NativeClockActions) } else { @() }
        storyModeCaptivityRecoveryVerified = if ($CaptivityRecoveryFromExisting -and $trace) { [bool]$trace.CaptivityRecoveryVerified } else { $null }
        storyModeGoldSaleSourceSave = if ($EstablishClanGoldSaleFromStoryMode) { $PlannerSourceSaveName } else { $null }
        storyModeGoldSaleSourceHashBefore = if ($EstablishClanGoldSaleFromStoryMode) { $plannerSourceHashBefore } else { $null }
        storyModeGoldSaleSourceHashAfter = if ($EstablishClanGoldSaleFromStoryMode) { $plannerSourceHashAfter } else { $null }
        storyModeGoldSaleFixtureRemoved = if ($EstablishClanGoldSaleFromStoryMode) { $plannerFixtureRemoved } else { $null }
        storyModeGoldSaleVerified = if ($EstablishClanGoldSaleFromStoryMode) { [bool]$trace.EstablishClanGoldSaleVerified } else { $null }
        storyModeGoldSaleVerification = if ($EstablishClanGoldSaleFromStoryMode) { $saleVerification } else { $null }
        storyModeGoldSaleBaseline = if ($EstablishClanGoldSaleFromStoryMode -and $trace) { $trace.EstablishClanGoldSaleBaseline } else { $null }
        battleTargetPreflight = if (($BattleSimulationLoop -or $BattleAndCaptivityLoop) -and $liveResult) { $liveResult.BattleTargetPreflight } else { $null }
        battleSourceSaveName = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { $BattleSourceSaveName } else { $null }
        battleSourceHashBefore = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { $battleSourceHashBefore } else { $null }
        battleSourceHashAfter = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { $battleSourceHashAfter } else { $null }
        battleDisposableSaveRemoved = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { $battleFixtureRemoved } else { $null }
        battleActionSequence = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { $battleActionSequence } else { @() }
        battleSimulationVerified = if (($BattleSimulationLoop -or $BattleAndCaptivityLoop) -and $trace) { [bool]$trace.BattleSimulationVerified } else { $null }
        captivityRecoveryVerified = if ($BattleAndCaptivityLoop -and $trace) { [bool]$trace.CaptivityRecoveryVerified } else { $null }
        renownBefore = if (($BattleSimulationLoop -or $BattleAndCaptivityLoop) -and $trace) { $trace.BattleRenownBefore } else { $null }
        renownAfter = if (($BattleSimulationLoop -or $BattleAndCaptivityLoop) -and $trace) { $trace.BattleRenownAfter } else { $null }
        observedIssueMarkerMatchedTalkTarget = if ($VillageToolsQuest) { [bool]$visibleIssueMarkerVerified } else { $null }
        nativeToolTradeCommits = if ($VillageToolsQuest) { @($tradeCommits | ForEach-Object { $_.actionReceipt.data }) } else { @() }
        preparedSaveRemoved = if ($BattleSimulationLoop -or $BattleAndCaptivityLoop) { $battleFixtureRemoved } else { $preparedSaveRemoved }
        trackedTreeClean = if ($trace) { [bool]$trace.SourceTrackedTreeClean } else { $false }
        decisions = if ($trace) { [int]$trace.Decisions } else { $null }
        nativeActions = $nativeActions.Count
        nativeArrivalVerified = if ($trace) { [bool]$trace.ArrivalConfirmed } else { $false }
        campaignTimeAdvancedNaturally = if ($trace) { [bool]$trace.CampaignDayAdvancedDuringTravel } else { $false }
        observeAgainCount = $observeAgainSteps.Count
        visualCoverageRatio = if ($liveResult) { [double]$liveResult.Capture.FrameCoverageRatio } else { $null }
        sourceVideoRemoved = if ($liveResult) { [bool]$liveResult.Capture.VideoRemovedAfterEvidence } else { $false }
        bannerlordProcessesStopped = $noGameProcesses
        cliSessionCleaned = $noSessionFile
        failure = $failure
        childOutput = if ($childExitCode -ne 0) { $childOutput } else { $null }
    })
    if (-not $passed) { break }
}

$result = [ordered]@{
    Passed = ($results.Count -eq $Runs -and @($results | Where-Object { $_.passed }).Count -eq $Runs)
    ProviderKind = if ($providerProfile -and -not [string]::IsNullOrWhiteSpace([string]$providerProfile.ProviderSource)) { [string]$providerProfile.ProviderSource } else { 'configured openai-compatible external provider' }
    RunCount = $Runs
    DistinctCampaignSeeds = 1
    Threshold = if ($CaptivityRecoveryFromExisting) {
        [ordered]@{
            successfulRuns = $Runs
            requiresNaturallyActiveEstablishYourClanQuest = 'rebuild_player_clan_storymode_quest'
            requiresNaturallyCaptiveMainHero = $true
            requiresNativePrisonerWaitAndRansomDecision = $true
            requiresExplicitResumeWhenStopAndWaitActive = $true
            passivelyWaitsWhenNativeTimeAlreadyFlows = $true
            requiresFreeMapAndUnmetObjectiveReplan = $true
            nativeGameplayActions = @('resume','menuSelect')
            explicitClockActionIsSeparate = $true
            sourceHashUnchangedAndDisposableCloneRemoved = $true
            visualCoverageRatio = 0.9
            fullStoryQuestCompletionClaimAllowed = $false
        }
    }
    elseif ($EstablishClanGoldSaleFromStoryMode) {
        [ordered]@{
            successfulRuns = $Runs
            requiresNaturallyActiveOriginalQuest = 'rebuild_player_clan_storymode_quest'
            goldJournalTarget = 2000
            nativeSaleUnitsPerRun = 1
            requiresCurrentTransferablePlayerInventoryGoodsOffer = $true
            requiresExactNativeGoldAndInventoryDelta = $true
            requiresOfficialJournalGoldProgressIncrease = $true
            allowW7OCaptivityPreludeWithoutBattle = $true
            explicitClockActionsOutsideW7OPrelude = 0
            fullQuestCompletionClaimAllowed = $false
            sourceHashUnchangedAndDisposableCloneRemoved = $true
            videoCoverageRatio = 0.9
        }
    }
    elseif ($EstablishYourClanAutonomyLoop) {
        [ordered]@{
            successfulRuns = $Runs
            sourceSaveIsDebugOnly = $PlannerSourceSaveName
            finalQuestRequiresNativeHistoryCompletion = $true
            requiresAllFourJournalObjectivesMet = $true
            sourceSaveMustRemainUnchanged = $true
            disposableClonePrefix = 'ChronicleW7P-'
            realNewCampaignAcceptanceGate = $false
            videoCoverageRatio = 0.9
        }
    }
    elseif ($EstablishYourClanGoalPlanner) {
        [ordered]@{
            successfulRuns = $Runs
            requiresNaturallyActiveOriginalQuest = 'rebuild_player_clan_storymode_quest'
            requiredObjectives = @('gold','partySize','renown','companions')
            requiresNativeJournalAndDynamicThresholdConsistency = $true
            requiresConfiguredOpenAiCompatibleModelDecision = $true
            nativeGameplayActionsAllowed = 0
            nativeReadOnlyQuestDetailsCalls = 1
            requiresWorldGoldPartyRenownQuestAndTimeUnchanged = $true
            sourceSaveHashMustRemainUnchanged = $true
            disposableClonePrefix = 'ChronicleW7N-'
            videoCoverageRatio = 0.9
            goalCompletionClaimAllowed = $false
        }
    }
    elseif ($BattleSimulationLoop -or $BattleAndCaptivityLoop) {
        [ordered]@{
            successfulRuns = $Runs
            targetMustBeCurrentNativeVisibleHostileBandit = $true
            acceptsCurrentNativeMeetingBranch = @('bandit_start_defender_1', 'common_encounter_ultimatum')
            ifCurrentNativeSurrenderOfferAppears = 'common_bandit_surrender_declined'
            everyDialogueChoiceMustMatchCurrentCatalogAndClickableOption = $true
            requiresNativeSendTroopsOption = 'str_order_attack'
            requiresBattleSimulationAndNativeAftermath = $true
            requiresReturnToMapAndRenownBeforeAfter = $true
            explicitClockActions = 0
            visualCoverageRatio = 0.9
        }
    }
    elseif ($VillageToolsQuest) {
        [ordered]@{
            successfulRuns = $Runs
            maximumTotalDecisions = 100
            requiredModelNativeActions = @('talkToSettlementHero','dialogueSelect','questDetails','tradeOptions','trade','tradeConfirm','inventoryOpen','heroEquipmentOptions','inventoryCancel')
            requiresVisibleNativeIssueMarker = $true
            requiresConfiguredOpenAiCompatibleRoutedModel = $true
            exactJournalInventoryDelta = $true
            explicitClockActions = 0
            visualCoverageRatio = 0.9
        }
    }
    else {
        [ordered]@{
            successfulRuns = $Runs
            maxDecisionsPerRun = 30
            nativeActions = 2
            requiredNativeActions = @('mapSettlementTargets', 'move')
            naturalCampaignTimeAdvance = $true
            requiredPassiveObservationsDuringMovement = $true
            explicitClockActions = 0
            visualCoverageRatio = 0.9
        }
    }
    Runs = @($results)
    EvidenceDirectory = $evaluationRoot
}
$result | ConvertTo-Json -Depth 14
if (-not $result.Passed) { exit 1 }
