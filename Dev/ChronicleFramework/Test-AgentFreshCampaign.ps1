[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 240,
    [switch]$StoryModeEycSetup,
    [switch]$StoryModeEycPersistentSeed,
    [string]$PersistentStoryModeSaveName,
    [switch]$StoryModeEycLiveModelEvaluation,
    [switch]$StoryModeNativeMenuLeaveEvaluation,
    [switch]$StoryModeNativeInquiryResponseEvaluation,
    [switch]$ValidateRecruitmentProgression,
    [switch]$RealModelRecruitment,
    [switch]$RetainDisposableSave,
    [switch]$TestAgentUsageTraceSummary
)

$ErrorActionPreference = 'Stop'
$harnessRoot = $PSScriptRoot
. (Join-Path $harnessRoot 'Test-AgentSupport.ps1')
. (Join-Path $harnessRoot 'HarnessShaderCacheDialog.ps1')
. (Join-Path $harnessRoot 'HarnessStartupEvidence.ps1')

function Measure-StoryModeAgentUsageFromTrace {
    param([AllowNull()][object[]]$Entries)

    $providerEvents = @($Entries | Where-Object { $_.event -eq 'provider-decision' })
    if ($providerEvents.Count -eq 0) {
        return [pscustomobject]@{ DecisionCount = 0; PromptTokens = 0; CompletionTokens = 0; PromptCacheHitTokens = $null; PromptCacheMissTokens = $null; EstimatedCostCny = $null; AllDecisionCostRowsPresent = $false; ReservedCostUpperBoundCny = $null }
    }

    $sumField = {
        param([string]$Name)
        $values = @($providerEvents | Where-Object { $null -ne $_.$Name } | ForEach-Object { [double]$_.$Name })
        if ($values.Count -eq 0) { return $null }
        return ($values | Measure-Object -Sum).Sum
    }
    $prompt = & $sumField 'promptTokens'
    $completion = & $sumField 'completionTokens'
    $cacheHitValues = @($providerEvents | Where-Object { $null -ne $_.promptCacheHitTokens } | ForEach-Object { [double]$_.promptCacheHitTokens })
    $cacheMissValues = @($providerEvents | Where-Object { $null -ne $_.promptCacheMissTokens } | ForEach-Object { [double]$_.promptCacheMissTokens })
    $costValues = @($providerEvents | Where-Object { $null -ne $_.estimatedCostCny } | ForEach-Object { [double]$_.estimatedCostCny })
    $reservedValues = @($providerEvents | Where-Object { $null -ne $_.reservedCostUpperBoundCny } | ForEach-Object { [double]$_.reservedCostUpperBoundCny })
    return [pscustomobject]@{
        DecisionCount = $providerEvents.Count
        PromptTokens = [long]$prompt
        CompletionTokens = [long]$completion
        PromptCacheHitTokens = if ($cacheHitValues.Count -eq $providerEvents.Count) { [long](($cacheHitValues | Measure-Object -Sum).Sum) } else { $null }
        PromptCacheMissTokens = if ($cacheMissValues.Count -eq $providerEvents.Count) { [long](($cacheMissValues | Measure-Object -Sum).Sum) } else { $null }
        EstimatedCostCny = if ($costValues.Count -gt 0) { [Math]::Round(($costValues | Measure-Object -Sum).Sum, 8) } else { $null }
        AllDecisionCostRowsPresent = $costValues.Count -eq $providerEvents.Count
        ReservedCostUpperBoundCny = if ($reservedValues.Count -gt 0) { [Math]::Round($reservedValues[-1], 8) } else { $null }
    }
}

if ($TestAgentUsageTraceSummary) {
    $sample = @(
        [pscustomobject]@{ event = 'provider-decision'; promptTokens = 100; completionTokens = 5; promptCacheHitTokens = 40; promptCacheMissTokens = 60; estimatedCostCny = 0.01; reservedCostUpperBoundCny = 0.02 },
        [pscustomobject]@{ event = 'objective-subflow-result'; promptTokens = 900; completionTokens = 900; estimatedCostCny = 900 },
        [pscustomobject]@{ event = 'provider-decision'; promptTokens = 200; completionTokens = 7; promptCacheHitTokens = 60; promptCacheMissTokens = 140; estimatedCostCny = 0.02; reservedCostUpperBoundCny = 0.05 }
    )
    $summary = Measure-StoryModeAgentUsageFromTrace $sample
    if ($summary.DecisionCount -ne 2 -or $summary.PromptTokens -ne 300 -or $summary.CompletionTokens -ne 12 -or
        $summary.PromptCacheHitTokens -ne 100 -or $summary.PromptCacheMissTokens -ne 200 -or
        [Math]::Abs($summary.EstimatedCostCny - 0.03) -gt 0.0000001 -or -not $summary.AllDecisionCostRowsPresent -or
        [Math]::Abs($summary.ReservedCostUpperBoundCny - 0.05) -gt 0.0000001) {
        throw 'StoryMode provider-usage trace aggregation did not preserve decision totals, cache/cost totals or the last cumulative reservation.'
    }
    $summary | ConvertTo-Json -Compress
    return
}
if ($StoryModeEycSetup -and [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { throw 'StoryModeEycSetup requires an active Run-Harness temp/evidence directory.' }
if ($StoryModeEycPersistentSeed -and (-not $StoryModeEycSetup -or $StoryModeNativeMenuLeaveEvaluation -or [string]::IsNullOrWhiteSpace($PersistentStoryModeSaveName))) {
    throw 'StoryModeEycPersistentSeed requires a StoryMode tutorial-skip run and a caller-owned disposable save name.'
}
if ($StoryModeEycPersistentSeed -and $PersistentStoryModeSaveName -notmatch '^[A-Za-z0-9_-]{1,48}$') { throw 'Persistent StoryMode save names must be 1-48 ASCII letters, digits, underscores or hyphens.' }
$storyModeEvidenceRoot = if ($StoryModeEycSetup) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { $null }
$gameRoot = if ($env:CHRONICLE_GAME_ROOT -and (Test-Path -LiteralPath $env:CHRONICLE_GAME_ROOT)) { [IO.Path]::GetFullPath($env:CHRONICLE_GAME_ROOT) } else { Split-Path -Parent (Split-Path -Parent $harnessRoot) }
$gameExe = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.exe'
$launcher = Join-Path $gameRoot 'bin\Win64_Shipping_Client\Bannerlord.BLSE.Standalone.exe'
$gameBinDirectory = Join-Path $gameRoot 'bin\Win64_Shipping_Client'
$steamRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $gameRoot))
$engineConfig = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\engine_config.txt'
$gameSoundDisabledBefore = Get-ChronicleBannerlordSoundDisabled -LiteralPath $engineConfig
$bannerlordAutoSavePaths = Get-ChronicleBannerlordAutoSavePaths
$bannerlordConfigPath = $bannerlordAutoSavePaths.ConfigPath
$diagnosticLog = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Configs\ModLogs\chronicle-framework.log'
$saveDirectory = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\Game Saves'
$autoSaveIntervalBefore = Get-ChronicleBannerlordAutoSaveInterval -LiteralPath $bannerlordConfigPath
$autoSaveIntervalDuring = $null
$autoSaveIntervalAfter = $null
$autoSaveSettingGuard = $null
$autoSaveSettingRestoration = $null
$autoSaveSettingRestorationError = $null
$gameSoundSettingGuard = $null
$gameSoundSettingRestoration = $null
$gameSoundSettingRestorationError = $null
$gameSoundDisabledDuring = $null
$gameSoundDisabledAfter = $null
$nativeAutoSaveDetected = $false
$agentCli = Join-Path $harnessRoot 'Agent-Cli.ps1'
$agentDecisionLoop = Join-Path $harnessRoot 'Agent-DecisionLoop.ps1'
$agentLoopProvider = Join-Path $harnessRoot 'Test-AgentLoopProvider.ps1'
$agentLiveModelLoop = Join-Path $harnessRoot 'Test-AgentLiveModelLoop.ps1'
$agentProtocolRoot = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent'
$agentSessionPath = Join-Path $agentProtocolRoot 'session.json'
$agentCommandPath = Join-Path $agentProtocolRoot 'command.json'
$agentResponseRoot = Join-Path $agentProtocolRoot 'responses'
$progressionCommandPrefix = 'freshp5-' + [Guid]::NewGuid().ToString('N')
$progressionSaveName = if ($ValidateRecruitmentProgression) { 'ChronicleP5Fresh-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8) } else { $null }
$progressionSavePath = if ($progressionSaveName) { Join-Path $saveDirectory "$progressionSaveName.sav" } else { $null }
$freshCampaignSaveName = if ($StoryModeEycPersistentSeed) { $PersistentStoryModeSaveName } elseif ($progressionSaveName) { $progressionSaveName } else { $null }
$persistentStoryModeSaveReadyFile = if ($StoryModeEycPersistentSeed) { Join-Path $env:CHRONICLE_HARNESS_TEMP ('persistent-storymode-save-ready-' + [Guid]::NewGuid().ToString('N') + '.flag') } else { $null }
$persistentStoryModeSaveTimeCheck = $null
$disposableSaveOwned = $false
$previousSessionExisted = Test-Path -LiteralPath $agentSessionPath
$previousSessionBytes = if ($previousSessionExisted) { [IO.File]::ReadAllBytes($agentSessionPath) } else { $null }
if ($ValidateRecruitmentProgression -and (Test-Path -LiteralPath $agentCommandPath)) { throw 'A pending Agent command exists; refusing to overwrite it for FreshCampaign progression.' }
if ($StoryModeEycSetup -and ($ValidateRecruitmentProgression -or $RealModelRecruitment -or ($RetainDisposableSave -and -not $StoryModeEycPersistentSeed))) { throw 'StoryModeEycSetup is a no-save Native StoryMode/tutorial-skip setup probe unless the dedicated persistent disposable StoryMode seed mode is selected.' }
if ($StoryModeEycLiveModelEvaluation -and (-not $StoryModeEycSetup -or $ValidateRecruitmentProgression -or $RealModelRecruitment -or $RetainDisposableSave)) { throw 'StoryModeEycLiveModelEvaluation requires the no-save StoryModeEycSetup path and cannot be combined with Sandbox progression or retained saves.' }
if ($StoryModeNativeMenuLeaveEvaluation -and (-not $StoryModeEycSetup -or $StoryModeEycLiveModelEvaluation -or $ValidateRecruitmentProgression -or $RealModelRecruitment -or $RetainDisposableSave)) { throw 'StoryModeNativeMenuLeaveEvaluation requires the no-save StoryModeEycSetup path and cannot be combined with a live-model run, Sandbox progression or retained saves.' }
if ($StoryModeNativeInquiryResponseEvaluation -and (-not $StoryModeNativeMenuLeaveEvaluation -or -not $StoryModeEycSetup)) { throw 'StoryModeNativeInquiryResponseEvaluation requires the no-save StoryModeNativeMenuLeaveEvaluation path.' }
if ($StoryModeNativeInquiryResponseEvaluation -and $previousSessionExisted) { throw 'The Native Inquiry callback test requires exclusive ownership of a temporary Agent CLI session; an existing session file will not be replaced.' }
if ($StoryModeNativeInquiryResponseEvaluation -and (Test-Path -LiteralPath $agentCommandPath)) { throw 'The Native Inquiry callback test will not overwrite a pending Agent CLI command.' }
if ($RealModelRecruitment -and -not $ValidateRecruitmentProgression) { throw 'RealModelRecruitment requires ValidateRecruitmentProgression so the new Campaign is saved as a protected disposable fixture before the model starts.' }
if ($RetainDisposableSave -and -not $ValidateRecruitmentProgression) { throw 'RetainDisposableSave requires ValidateRecruitmentProgression so only a verified Native New Campaign save can be retained.' }
if ($progressionSavePath -and (Test-Path -LiteralPath $progressionSavePath)) { throw 'Generated disposable-save name already exists; refusing to overwrite.' }
$persistentStoryModeSavePath = if ($StoryModeEycPersistentSeed) { Join-Path $saveDirectory "$PersistentStoryModeSaveName.sav" } else { $null }
if ($persistentStoryModeSavePath -and (Test-Path -LiteralPath $persistentStoryModeSavePath)) { throw 'Persistent StoryMode seed name already exists; refusing to overwrite a save not created by this run.' }
. (Join-Path $harnessRoot 'Test-WindowLayout.ps1')

function Invoke-FreshCampaignAgentCli([string]$Action, [string[]]$Arguments = @{}, [int]$CommandTimeout = 15) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $agentCli $Action @Arguments -TimeoutSeconds $CommandTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "FreshCampaign Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "FreshCampaign Agent CLI '$Action' returned invalid JSON: $output" }
}

if (-not (Test-Path -LiteralPath $gameExe)) { throw "Bannerlord executable was not found: $gameExe" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'A Bannerlord client is already running.' }
if (-not (Test-Path -LiteralPath $engineConfig)) { throw "Windowed display config was not found: $engineConfig" }
$currentEngineConfig = Get-Content -LiteralPath $engineConfig -Raw
if ($currentEngineConfig -notmatch '(?m)^display_mode\s*=\s*0\s*$' -or
    $currentEngineConfig -notmatch '(?m)^display_width\s*=\s*840\s*$' -or
    $currentEngineConfig -notmatch '(?m)^display_height\s*=\s*472\s*$') {
    throw 'FreshCampaign requires the existing 840x472 windowed test profile; it will not change display layout.'
}

function Get-DescendantProcessIds([int]$ParentId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        [int]$child.ProcessId
        Get-DescendantProcessIds -ParentId $child.ProcessId
    }
}

function Set-SafeExitMarker {
    if (-not (Test-Path -LiteralPath $engineConfig)) { return }
    $text = Get-Content -LiteralPath $engineConfig -Raw
    $text = $text -replace 'safely_exited\s*=\s*0', 'safely_exited = 1'
    Set-Content -LiteralPath $engineConfig -Value $text -NoNewline
}

function Get-SaveManifestDigest([string]$ExcludeSaveName = '') {
    if (-not (Test-Path -LiteralPath $saveDirectory)) { return 'no-save-directory' }
    $excludedFileName = if ([string]::IsNullOrWhiteSpace($ExcludeSaveName)) { $null } else { "$ExcludeSaveName.sav" }
    $manifest = @(Get-ChildItem -LiteralPath $saveDirectory -File -Filter '*.sav' | Where-Object { $_.Name -cne $excludedFileName } | Sort-Object Name | ForEach-Object {
        "$($_.Name)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)"
    }) -join "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($manifest)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') } finally { $sha.Dispose() }
}

$modules = @(
    'Bannerlord.Harmony', 'Bannerlord.ButterLib', 'Bannerlord.UIExtenderEx', 'Bannerlord.MBOptionScreen',
    'Native', 'SandBoxCore', 'CustomBattle', 'SandBox', 'StoryMode', 'BirthAndDeath', 'ChronicleFramework'
)
$moduleArgument = '_MODULES_*' + ($modules -join '*') + '*_MODULES_'
$arguments = "/singleplayer $moduleArgument /anticheat /no_watchdog"
$saveDigestBefore = Get-SaveManifestDigest
$diagnosticStartLineCount = if (Test-Path -LiteralPath $diagnosticLog) { @(Get-Content -LiteralPath $diagnosticLog -Encoding UTF8).Count } else { 0 }
$launchStart = Get-Date
$previousMode = $env:CHRONICLE_HARNESS_MODE
$previousStoryModeFlag = $env:CHRONICLE_FRESH_CAMPAIGN_STORYMODE
$previousStoryModeStartAgent = $env:CHRONICLE_FRESH_CAMPAIGN_START_AGENT
$previousStoryModeNativeMenuLeaveTest = $env:CHRONICLE_FRESH_CAMPAIGN_NATIVE_MENU_LEAVE_TEST
$providerEnvironmentNames = @(
    'CHRONICLE_LLM_BASE_URL','CHRONICLE_LLM_MODEL','CHRONICLE_LLM_API_KEY','FREELLMAPI_API_KEY',
    'CHRONICLE_LLM_PROTOCOL','CHRONICLE_LLM_MAX_TOKENS','CHRONICLE_LLM_MAX_TOKEN_PARAMETER',
    'CHRONICLE_LLM_THINKING_MODE','CHRONICLE_LLM_REASONING_EFFORT','CHRONICLE_LLM_TIMEOUT_SECONDS',
    'CHRONICLE_LLM_OUTPUT_MODE','CHRONICLE_LLM_MAX_RUN_COST_CNY'
)
$providerEnvironmentImportNames = @($providerEnvironmentNames | Where-Object { $_ -notin @('CHRONICLE_LLM_API_KEY','FREELLMAPI_API_KEY') })
$previousProviderEnvironment = [ordered]@{}
foreach ($name in $providerEnvironmentNames) { $previousProviderEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$previousIssueProbeFlag = $env:CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE
$previousFreshSaveName = $env:CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME
$previousFreshSaveReadyFile = $env:CHRONICLE_FRESH_CAMPAIGN_SAVE_READY_FILE
$previousCrashCaptureFlag = $env:CHRONICLE_CAPTURE_CRASH_EXCEPTION
$env:CHRONICLE_HARNESS_MODE = 'fresh-campaign-renown'
if ($StoryModeEycSetup) { $env:CHRONICLE_FRESH_CAMPAIGN_STORYMODE = '1' }
else { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_STORYMODE -ErrorAction SilentlyContinue }
if ($StoryModeEycLiveModelEvaluation) { $env:CHRONICLE_FRESH_CAMPAIGN_START_AGENT = '1' }
else { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_START_AGENT -ErrorAction SilentlyContinue }
if ($StoryModeNativeMenuLeaveEvaluation) { $env:CHRONICLE_FRESH_CAMPAIGN_NATIVE_MENU_LEAVE_TEST = '1' }
else { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_NATIVE_MENU_LEAVE_TEST -ErrorAction SilentlyContinue }
$env:CHRONICLE_CAPTURE_CRASH_EXCEPTION = '1'
$freeLlmApiProfile = $null
$providerProfile = $null
if ($ValidateRecruitmentProgression -or $RetainDisposableSave -or $StoryModeEycPersistentSeed) {
    $env:CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE = '1'
    $env:CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME = $freshCampaignSaveName
}
if ($StoryModeEycPersistentSeed) {
    $env:CHRONICLE_FRESH_CAMPAIGN_SAVE_READY_FILE = $persistentStoryModeSaveReadyFile
} else {
    Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_SAVE_READY_FILE -ErrorAction SilentlyContinue
}
try {
    if ($StoryModeEycLiveModelEvaluation) {
        foreach ($name in $providerEnvironmentImportNames) {
            if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name,'Process'))) {
                $userValue = [Environment]::GetEnvironmentVariable($name,'User')
                if (-not [string]::IsNullOrWhiteSpace($userValue)) { [Environment]::SetEnvironmentVariable($name,$userValue,'Process') }
            }
        }
        $providerBaseUrl = [string]$env:CHRONICLE_LLM_BASE_URL
        $providerModelId = [string]$env:CHRONICLE_LLM_MODEL
        $providerUri = $null
        if ([string]::IsNullOrWhiteSpace($providerModelId) -or -not [Uri]::TryCreate($providerBaseUrl,[UriKind]::Absolute,[ref]$providerUri)) {
            throw 'StoryMode live-model preflight requires the configured provider base URL and model ID; Bannerlord was not started.'
        }
        . (Join-Path $harnessRoot 'Get-FreeLLMAPIProfile.ps1')
        $providerCredential = Get-ChronicleProviderCredential -Endpoint $providerUri
        $providerApiKey = [string]$providerCredential.Value
        if ($providerUri.IsLoopback -and $providerUri.Port -eq 31415 -and $providerUri.AbsolutePath.TrimEnd('/') -eq '/v1') {
            if ([string]::IsNullOrWhiteSpace($providerApiKey)) { throw 'FreeLLMAPI client key is unavailable; Bannerlord was not started and no key value was displayed.' }
            $freeLlmApiProfile = Initialize-FreeLLMAPIProfile
            if ($freeLlmApiProfile.ModelExecutionStatus -notin @('ready','router')) { throw 'Configured FreeLLMAPI model is not currently available; Bannerlord was not started.' }
            $providerProfile = [pscustomobject]@{ ProviderHost=$providerUri.Host; ModelId=$providerModelId; OutputMode=[string]$env:CHRONICLE_LLM_OUTPUT_MODE; DeepSeekRunCostLimitCny=[double]$env:CHRONICLE_LLM_MAX_RUN_COST_CNY; CatalogListed=$true; FreeLLMAPI=$true }
        }
        else {
            if ($providerUri.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($providerApiKey)) {
                throw 'Remote StoryMode model preflight requires HTTPS and CHRONICLE_LLM_API_KEY; Bannerlord was not started.'
            }
            $modelsUri = [UriBuilder]::new($providerUri)
            $modelsUri.Path = $providerUri.AbsolutePath.TrimEnd('/') + '/models'
            $modelsUri.Query = ''
            try { $modelRows = @(Invoke-RestMethod -Uri $modelsUri.Uri -Headers @{ Authorization="Bearer $providerApiKey" } -TimeoutSec 15 | Select-Object -ExpandProperty data) }
            catch { throw 'Remote provider read-only /models preflight failed; no inference request was sent and Bannerlord was not started.' }
            if (-not @($modelRows | Where-Object { [string]$_.id -ceq $providerModelId }).Count) {
                throw 'Configured model ID is absent from the remote provider catalog; Bannerlord was not started.'
            }
            $providerProfile = [pscustomobject]@{ ProviderHost=$providerUri.Host; ModelId=$providerModelId; OutputMode=[string]$env:CHRONICLE_LLM_OUTPUT_MODE; DeepSeekRunCostLimitCny=[double]$env:CHRONICLE_LLM_MAX_RUN_COST_CNY; CatalogListed=$true; FreeLLMAPI=$false; AvailableModelCount=$modelRows.Count }
        }
        $providerApiKey = $null
    }
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'BLSE standalone launcher was not found in the configured Bannerlord installation.' }
    $steamReadiness = Ensure-ChronicleSteamClientReady -SteamRoot $steamRoot -TimeoutSeconds 45
    if (-not $steamReadiness.Readiness.Ready) { throw 'Steam did not reach the stable WebHelper readiness gate; FreshCampaign launch was refused.' }
    $autoSaveSettingGuard = Disable-ChronicleHarnessAutoSave
    $autoSaveIntervalDuring = Get-ChronicleBannerlordAutoSaveInterval -LiteralPath $bannerlordConfigPath
    if ($autoSaveIntervalDuring -ne -1) { throw 'Native Bannerlord auto-save must be disabled for every FreshCampaign fixture before the game can start.' }
    $gameSoundDisabledBefore = Get-ChronicleBannerlordSoundDisabled -LiteralPath $engineConfig
    $gameSoundSettingGuard = Disable-ChronicleHarnessGameSound
    $gameSoundDisabledDuring = Get-ChronicleBannerlordSoundDisabled -LiteralPath $engineConfig
    if ($gameSoundDisabledDuring -ne 1) { throw 'Bannerlord audio must be disabled by the temporary Harness engine-config guard before the game can start.' }
    Set-SafeExitMarker
    $launcherProcess = Start-ChronicleSteamGame -FilePath $launcher -ArgumentList $arguments -WorkingDirectory $gameBinDirectory -WindowStyle Minimized
}
catch {
    if ($autoSaveSettingGuard) {
        try { $autoSaveSettingRestoration = Restore-ChronicleHarnessAutoSaveSetting }
        catch { $autoSaveSettingRestorationError = $_.Exception.Message }
    }
    if ($gameSoundSettingGuard) {
        try { $gameSoundSettingRestoration = Restore-ChronicleHarnessGameSound }
        catch { $gameSoundSettingRestorationError = $_.Exception.Message }
    }
    throw
}
finally {
    $env:CHRONICLE_HARNESS_MODE = $previousMode
    if ($null -eq $previousStoryModeFlag) { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_STORYMODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_FRESH_CAMPAIGN_STORYMODE = $previousStoryModeFlag }
    if ($null -eq $previousStoryModeStartAgent) { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_START_AGENT -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_FRESH_CAMPAIGN_START_AGENT = $previousStoryModeStartAgent }
    if ($null -eq $previousStoryModeNativeMenuLeaveTest) { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_NATIVE_MENU_LEAVE_TEST -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_FRESH_CAMPAIGN_NATIVE_MENU_LEAVE_TEST = $previousStoryModeNativeMenuLeaveTest }
    foreach ($name in $providerEnvironmentNames) {
        $previousValue = [string]$previousProviderEnvironment[$name]
        if ([string]::IsNullOrEmpty($previousValue)) { Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name,$previousValue,'Process') }
    }
    if ($null -eq $previousCrashCaptureFlag) { Remove-Item Env:CHRONICLE_CAPTURE_CRASH_EXCEPTION -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_CAPTURE_CRASH_EXCEPTION = $previousCrashCaptureFlag }
            if ($null -eq $previousIssueProbeFlag) { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_FRESH_CAMPAIGN_SKIP_ISSUE_PROBE = $previousIssueProbeFlag }
    if ($null -eq $previousFreshSaveName) { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_FRESH_CAMPAIGN_SAVE_NAME = $previousFreshSaveName }
    if ($null -eq $previousFreshSaveReadyFile) { Remove-Item Env:CHRONICLE_FRESH_CAMPAIGN_SAVE_READY_FILE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_FRESH_CAMPAIGN_SAVE_READY_FILE = $previousFreshSaveReadyFile }
    if ($persistentStoryModeSaveReadyFile -and (Test-Path -LiteralPath $persistentStoryModeSaveReadyFile -PathType Leaf)) {
        $tempRoot = [IO.Path]::GetFullPath($env:CHRONICLE_HARNESS_TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $fullReadySignalPath = [IO.Path]::GetFullPath($persistentStoryModeSaveReadyFile)
        if (-not $fullReadySignalPath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Persistent StoryMode ready-signal cleanup path escaped the Harness temp directory.' }
        Remove-Item -LiteralPath $fullReadySignalPath -Force
    }
}

$bannerlordPid = 0
$gameStarted = $false
$startRequested = $false
$introSkippedObserved = $false
$startupDialogReceipts = [System.Collections.Generic.List[object]]::new()
$startupDialogSnapshots = [System.Collections.Generic.List[object]]::new()
$startupDialogFailure = $null
$creationCompleted = $false
$initialSnapshotCaptured = $false
$storyModeTutorialSkipSelected = $false
$storyModeTutorialSkipConfirmed = $false
$storyModeMapReadyObserved = $false
$storyModeMapSettledObserved = $false
$storyModeMapMenuId = $null
$storyModeMapSettlementId = $null
$storyModeEycReadyObserved = $false
$storyModeRenderSettledObserved = $false
$storyModeAgentHostStarted = $false
$storyModeAgentHostReady = $false
$storyModeAgentHostStartRequested = $false
$storyModeTutorialSkipConfirmedAt = $null
$storyModeAgentHostStartRequestedAt = $null
$storyModeStartupFailure = $null
$storyModeFocusLossEscapeMenuGuardInstalled = $false
$storyModeAgentHostTerminalDetail = $null
$storyModeNativeLeaveRequested = $false
$storyModeNativeLeaveVerified = $false
$storyModeNativeLeaveFailure = $null
$storyModeNativeLeaveBeforeMenu = $null
$storyModeNativeLeaveAfterMenu = $null
$storyModeNativeLeaveAfterSettlement = $null
$storyModeNativeLeaveCampaignDayBefore = $null
$storyModeNativeLeaveCampaignDayAfter = $null
$storyModeNativeLeaveClockAfter = $null
$storyModeNativeLeavePostActionSnapshot = $null
$storyModeNativeInquiryResponseRequested = $false
$storyModeNativeInquiryResponseVerified = $false
$storyModeNativeInquiryResponseFailure = $null
$storyModeNativeInquiryResponseReceipt = $null
$storyModeNativeInquiryStateAfterResponse = $null
$storyModeNativeInquiryBeforeDay = $null
$storyModeNativeInquiryAfterDay = $null
$storyModeNativeInquiryTestSessionCreated = $false
$storyModeNativeInquiryResponseCommandId = $null
$storyModeNativeInquiryStateCommandId = $null
$storyModeAgentHostTerminalState = $null
$storyModeAgentHostReceiptCaptured = $false
$storyModeAgentUsageSource = 'unavailable'
$storyModeAgentProviderDecisionCostsComplete = $false
$storyModeAgentNativeActionTraceObserved = $false
$storyModeAgentProgressLineCount = 0
$storyModeAgentProgressEntries = [System.Collections.Generic.List[object]]::new()
$storyModeAgentNativeActionsExecuted = 0
$storyModeAgentDecisionCount = 0
$storyModeAgentPromptTokens = 0
$storyModeAgentCompletionTokens = 0
$storyModeAgentPromptCacheHitTokens = $null
$storyModeAgentPromptCacheMissTokens = $null
$storyModeAgentActualCostEstimateCny = $null
$storyModeAgentReservedCostUpperBoundCny = $null
$storyModeAgentFailureCode = $null
$storyModeAgentFailureExceptionType = $null
$storyModeAgentFailureLocation = $null
$storyModeOriginalEstablishYourClanCompleted = $false
$storyModeAgentHostReceiptPath = if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $null } else { Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentHostLifecycleHostReceipt.json' }
$storyModeNativeFrameNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$storyModeNativeFrameHashes = [ordered]@{}
$snapshotArtifactPath = if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $null } else { Join-Path $env:CHRONICLE_HARNESS_TEMP 'FreshCampaign.initial-state.json' }
$storyModeFirstMapSnapshotPath = if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { $null } else { Join-Path $env:CHRONICLE_HARNESS_TEMP 'FreshStoryMode.post-skip-map-state.json' }
$renown = $null
$campaignInstanceId = $null
$mapState = $null
$clock = $null
$stageIndices = [System.Collections.Generic.HashSet[int]]::new()
$backgroundChoiceObserved = $false
$visibleIssuePoolObserved = $false
$visibleIssueTypes = $null
$issueConversationProbeStatus = 'not-observed'
$issueConversationOfferOption = $false
$issueConversationBriefReached = $false
$issueConversationOfferDenied = $false
$issueQuestAcceptanceAvailable = $false
$issueConversationClockBefore = $null
$issueConversationClockAfter = $null
$issueConversationOptions = @()
$harnessFailureObserved = $false
$campaignSaveRequested = $false
$persistentStoryModeSaveOwned = $false
$persistentStoryModeSaveCompleted = $false
$persistentStoryModeSaveReadySignaled = $false
$persistentStoryModeSaveHash = $null
$crashDetected = $false
$windowLayoutApplied = $false
$windowLayout = $null
$crashWindowTitle = $null
$crashWindowCapture = $null
$crashWindowCaptureResult = $null
$crashWindowCaptureError = $null
$crashWindowCaptureAttempted = $false
$crashWindowCaptureUntil = $null
$crashWindowCapturePath = $null
$crashWindowEventTracePath = $null
$crashWindowCaptureRetained = $false
$crashModulesCaptured = $false
$crashFaultAddress = $null
$crashFaultModule = $null
$crashModuleInventory = @()
$crashModuleCaptureError = $null
$rglLog = $null
$watchdogLog = $null
$recruitmentProgression = $null
$recruitmentProgressionError = $null
$recruitmentProgressionPassed = -not $ValidateRecruitmentProgression
$disposableSaveRequested = $false
$disposableSaveCompleted = $false
$disposableSaveSuccessful = $false
$disposableSaveFailed = $false
$storyModeVideoCapture = $null
$storyModeVideoCaptureResult = $null
$storyModeVideoCaptureError = $null
$storyModeVideoCaptureAttempted = $false
$storyModeVideoCaptureActive = $false
$storyModeVideoCaptureRetained = $false
$storyModeVideoStartedTicks = 0L
$storyModeVideoFrequency = [Diagnostics.Stopwatch]::Frequency
$storyModeVideoPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'FreshStoryModeSetup.mp4' } else { $null }
$storyModeVideoEventsPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'FreshStoryModeSetup-events.jsonl' } else { $null }
$storyModeNativeLeaveSnapshotPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'FreshStoryMode.native-menu-leave.json' } else { $null }
$storyModeTrainingFieldExitPath = $null
$storyModeAgentProgressPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'AgentHostProgress.jsonl' } else { $null }
$storyModeFreeLLMAPIUpstreamTrace = [pscustomobject]@{ Status = 'not-applicable'; Attempts = @() }
$storyModeVideoContactPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'FreshStoryModeSetup-contact.jpg' } else { $null }
$deadline = (Get-Date).AddSeconds($(if ($ValidateRecruitmentProgression) { [Math]::Min(90, $TimeoutSeconds) } else { $TimeoutSeconds }))

function Write-StoryModeCaptureEvent([string]$EventName, [string]$Action, [string]$Status, [string]$GameState, [string]$MenuId) {
    if (-not $script:storyModeVideoCaptureActive -or -not $script:storyModeVideoEventsPath) { return }
    $nowTicks = [Diagnostics.Stopwatch]::GetTimestamp()
    $event = [ordered]@{
        event = $EventName
        action = $Action
        commandId = 'fresh-storymode-' + $EventName
        status = $Status
        gameState = $GameState
        menuId = $MenuId
        partyScreenMode = ''
        inventoryMode = ''
        utc = (Get-Date).ToUniversalTime().ToString('O')
        offsetMilliseconds = [Math]::Round(($nowTicks - $script:storyModeVideoStartedTicks) * 1000.0 / $script:storyModeVideoFrequency, 2)
    }
    [IO.File]::AppendAllText($script:storyModeVideoEventsPath, (ConvertTo-Json -InputObject $event -Compress) + [Environment]::NewLine, [Text.Encoding]::UTF8)
}

try {
    while ((Get-Date) -lt $deadline) {
        $candidate = Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue |
            Where-Object { $_.StartTime -ge $launchStart } |
            Sort-Object StartTime |
            Select-Object -Last 1
        if ($candidate) {
            $bannerlordPid = $candidate.Id
            $crashWindowTitle = [string]$candidate.MainWindowTitle
            if ($crashWindowTitle -match '(?i)Crash Report|CrashReporter') { $crashDetected = $true }
            if ($candidate.MainWindowTitle -ceq 'Mod change detected') {
                try {
                    $dialogResult = Invoke-ChronicleShaderCacheDialogAcknowledgement -ProcessId $bannerlordPid -WindowHandle $candidate.MainWindowHandle
                }
                catch {
                    $dialogEvidencePath = if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) { Join-Path $env:CHRONICLE_HARNESS_TEMP "startup-dialog-$bannerlordPid.json" } else { $null }
                    if ($dialogEvidencePath) { [pscustomobject]@{ Handled = $false; ProcessId = $bannerlordPid; WindowTitle = $candidate.MainWindowTitle; Error = $_.Exception.Message } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $dialogEvidencePath -Encoding UTF8 }
                    $startupDialogFailure = "Safe handling of the known shader-cache prompt failed before confirmation. No global keyboard or mouse input was sent. Cause: $($_.Exception.Message)"
                    $harnessFailureObserved = $true
                    break
                }
                $startupDialogReceipts.Add($dialogResult)
                if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) {
                    $dialogEvidencePath = Join-Path $env:CHRONICLE_HARNESS_TEMP "startup-dialog-$bannerlordPid.json"
                    $dialogResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $dialogEvidencePath -Encoding UTF8
                }
                if (-not $dialogResult.Handled) {
                    $startupDialogFailure = "Known shader-cache prompt did not satisfy its exact UIA/Button process-ownership checks. No button was pressed; evidence: $dialogEvidencePath"
                    $harnessFailureObserved = $true
                    break
                }
                Start-Sleep -Milliseconds 200
                continue
            }
            $isBannerlordWindow = [string]$candidate.MainWindowTitle -match '(?i)Bannerlord'
            if ($isBannerlordWindow) {
                $windowLayout = Set-ChronicleTestWindow -ProcessId $bannerlordPid
                if ($windowLayout) { $windowLayoutApplied = [bool]$windowLayout.Applied }
            }
            elseif ($candidate.MainWindowHandle -ne [IntPtr]::Zero -and -not [string]::IsNullOrWhiteSpace([string]$candidate.MainWindowTitle) -and
                -not @($startupDialogSnapshots | Where-Object { $_.ProcessId -eq $bannerlordPid -and $_.WindowTitle -ceq [string]$candidate.MainWindowTitle }).Count) {
                try {
                    $unknownWindow = Get-ChronicleWindowAutomationSnapshot -ProcessId $bannerlordPid -WindowHandle ([IntPtr]$candidate.MainWindowHandle)
                    $startupDialogSnapshots.Add($unknownWindow)
                    if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) {
                        $snapshotPath = Join-Path $env:CHRONICLE_HARNESS_TEMP "startup-window-$bannerlordPid.json"
                        $unknownWindow | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8
                    }
                }
                catch { $startupDialogSnapshots.Add([pscustomobject]@{ ProcessId = $bannerlordPid; WindowTitle = [string]$candidate.MainWindowTitle; Error = $_.Exception.Message }) }
            }
            if ($StoryModeEycSetup -and $isBannerlordWindow -and -not $storyModeVideoCaptureAttempted -and $candidate.MainWindowHandle -ne [IntPtr]::Zero -and $windowLayout -and $windowLayout.Applied) {
                if ([string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP) -or
                    (Test-Path -LiteralPath $storyModeVideoPath) -or (Test-Path -LiteralPath $storyModeVideoEventsPath)) {
                    $storyModeVideoCaptureError = 'Harness temp path is unavailable or the unique story setup capture path already exists.'
                    $harnessFailureObserved = $true
                    break
                }
                $storyModeVideoCaptureAttempted = $true
                try {
                    . (Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1')
                    [IO.File]::WriteAllText($storyModeVideoEventsPath, '', [Text.Encoding]::UTF8)
                    $storyModeVideoCapture = Start-ChronicleWindowVideoCapture -ProcessId $bannerlordPid -OutputPath $storyModeVideoPath -FrameRate 10
                    $storyModeVideoStartedTicks = $storyModeVideoCapture.StartedTicks
                    $storyModeVideoFrequency = $storyModeVideoCapture.StopwatchFrequency
                    $storyModeVideoCaptureActive = $true
                    Write-StoryModeCaptureEvent 'capture-start' 'capture' 'completed' 'Startup' ''
                }
                catch {
                    $storyModeVideoCaptureError = $_.Exception.Message
                    $harnessFailureObserved = $true
                    break
                }
            }
            if ($crashWindowTitle -match '(?i)Crash Report|CrashReporter' -and -not $crashWindowCaptureAttempted) {
                $crashWindowCaptureAttempted = $true
                if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) {
                    try {
                        . (Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1')
                        $crashWindowCapturePath = Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashReport-$bannerlordPid.mp4"
                        $crashWindowCapture = Start-ChronicleWindowVideoCapture -ProcessId $bannerlordPid -OutputPath $crashWindowCapturePath -FrameRate 10
                        $crashWindowEventTracePath = Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashReport-$bannerlordPid-events.jsonl"
                        $crashEvent = [ordered]@{ event = 'crash-report-visible'; action = 'crashReport'; commandId = "crash-$bannerlordPid"; gameState = 'CrashReport'; menuId = ''; partyScreenMode = ''; inventoryMode = ''; utc = (Get-Date).ToUniversalTime().ToString('O'); offsetMilliseconds = 1000 }
                        [IO.File]::WriteAllText($crashWindowEventTracePath, (ConvertTo-Json -InputObject $crashEvent -Compress) + [Environment]::NewLine, [Text.Encoding]::UTF8)
                        $crashWindowCaptureUntil = (Get-Date).AddSeconds(2.2)
                    }
                    catch { $crashWindowCaptureError = $_.Exception.Message }
                }
                else { $crashWindowCaptureError = 'Harness temp directory is unavailable.' }
            }
            $rglLog = Join-Path $env:ProgramData "Mount and Blade II Bannerlord\logs\rgl_log_$bannerlordPid.txt"
            $watchdogLog = Join-Path $env:ProgramData "Mount and Blade II Bannerlord\logs\watchdog_log_$bannerlordPid.txt"
        }

        $newLines = @()
        if (Test-Path -LiteralPath $diagnosticLog) {
            $allLines = @(Get-Content -LiteralPath $diagnosticLog -Encoding UTF8)
            if ($allLines.Count -gt $diagnosticStartLineCount) {
                $newLines = @($allLines[$diagnosticStartLineCount..($allLines.Count - 1)])
                $diagnosticStartLineCount = $allLines.Count
            }
        }
        $gameStarted = $gameStarted -or [bool]($newLines -match "pid=$bannerlordPid\|game-start$")
        if ($StoryModeEycLiveModelEvaluation) {
            foreach ($line in $newLines) {
                if ($line -match "pid=$bannerlordPid\|harness-focus-loss-escape-guard-installed\|scope=(visual-capture|agent-host-lifecycle-test|fresh-campaign-renown)$") { $storyModeFocusLossEscapeMenuGuardInstalled = $true }
                if ($line -match "pid=$bannerlordPid\|harness-agent-lifecycle-auto-start$") { $storyModeAgentHostStartRequested = $true; if (-not $storyModeAgentHostStartRequestedAt) { $storyModeAgentHostStartRequestedAt = Get-Date } }
                if ($line -match "pid=$bannerlordPid\|agent-host-state\|state=Starting\|") { $storyModeAgentHostStartRequested = $true; if (-not $storyModeAgentHostStartRequestedAt) { $storyModeAgentHostStartRequestedAt = Get-Date } }
                if ($line -match "pid=$bannerlordPid\|agent-host-process-started\|pid=(\d+)\|") { $storyModeAgentHostStarted = $true }
                if ($line -match "pid=$bannerlordPid\|agent-host-ready\|hostPid=(\d+)\|") { $storyModeAgentHostReady = $true; Write-StoryModeCaptureEvent 'agent-host-ready' 'hostReady' 'completed' 'MapState' '' }
                if ($line -match "pid=$bannerlordPid\|agent-host-state\|state=(Stopped|Completed|Failed)\|detail=(.*)$") { $storyModeAgentHostTerminalState = $Matches[1]; $storyModeAgentHostTerminalDetail = $Matches[2]; Write-StoryModeCaptureEvent 'agent-host-terminal' $storyModeAgentHostTerminalState 'completed' 'MapState' '' }
            }
            if ($storyModeAgentProgressPath -and (Test-Path -LiteralPath $storyModeAgentProgressPath -PathType Leaf)) {
                $progressLines = @(Get-Content -LiteralPath $storyModeAgentProgressPath -Encoding UTF8)
                if ($progressLines.Count -gt $storyModeAgentProgressLineCount) {
                    foreach ($progressLine in $progressLines[$storyModeAgentProgressLineCount..($progressLines.Count - 1)]) {
                        try {
                            $entry = $progressLine | ConvertFrom-Json
                            $storyModeAgentProgressEntries.Add($entry)
                            $decisionAction = [string]$entry.decision.action
                            $decisionState = [string]$entry.observation.gameState
                            $decisionMenu = [string]$entry.observation.menuId
                            Write-StoryModeCaptureEvent 'agent-provider-decision' $decisionAction 'modelDecision' $decisionState $decisionMenu
                        }
                        catch { $harnessFailureObserved = $true }
                    }
                    $storyModeAgentProgressLineCount = $progressLines.Count
                }
            }
        }
        if ($StoryModeNativeMenuLeaveEvaluation) {
            foreach ($line in $newLines) {
                if ($line -match "pid=$bannerlordPid\|fresh-storymode-native-menu-leave\|status=requested\|") {
                    $storyModeNativeLeaveRequested = $true
                    Write-StoryModeCaptureEvent 'native-training-field-leave-requested' 'menuSelect' 'completed' 'MapState' 'training_field_menu'
                }
                if ($line -match 'fresh-storymode-native-menu-leave\|status=verified\|beforeMenu=([^|]+)\|afterMenu=([^|]+)\|afterSettlement=([^|]+)\|campaignDayBefore=([0-9.]+)\|campaignDayAfter=([0-9.]+)\|clock=([^|]+)\|eycActive=(True|False)$') {
                    $storyModeNativeLeaveRequested = $true
                    $storyModeNativeLeaveVerified = $true
                    $storyModeNativeLeaveBeforeMenu = $Matches[1]
                    $storyModeNativeLeaveAfterMenu = $Matches[2]
                    $storyModeNativeLeaveAfterSettlement = $Matches[3]
                    $storyModeNativeLeaveCampaignDayBefore = [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture)
                    $storyModeNativeLeaveCampaignDayAfter = [double]::Parse($Matches[5], [Globalization.CultureInfo]::InvariantCulture)
                    $storyModeNativeLeaveClockAfter = $Matches[6]
                    $storyModeEycReadyObserved = $storyModeEycReadyObserved -and $Matches[7] -eq 'True'
                    Write-StoryModeCaptureEvent 'native-training-field-leave-verified' 'menuSelect' 'completed' 'MapState' $storyModeNativeLeaveAfterMenu
                }
                if ($line -match 'fresh-storymode-native-menu-leave\|status=(failed|unverified)\|detail=(.*)$') {
                    $storyModeNativeLeaveFailure = [string]$Matches[2]
                    $harnessFailureObserved = $true
                }
                if ($line -match 'fresh-storymode-native-menu-leave-snapshot\|json=(\{.*\})$') {
                    try {
                        if (-not $storyModeNativeLeaveSnapshotPath) { throw 'Harness temp path is unavailable for the post-Leave observation.' }
                        [IO.File]::WriteAllBytes($storyModeNativeLeaveSnapshotPath, [Text.Encoding]::UTF8.GetBytes($Matches[1]))
                        $storyModeNativeLeavePostActionSnapshot = $Matches[1] | ConvertFrom-Json
                        if ($StoryModeNativeInquiryResponseEvaluation) {
                            $inquiry = $storyModeNativeLeavePostActionSnapshot.context.inquiry
                            if (-not $storyModeNativeLeavePostActionSnapshot.context.inquiryOpen -or
                                -not $inquiry.supported -or $inquiry.kind -ne 'YesNoInquiry' -or
                                -not $inquiry.affirmative.visible -or -not $inquiry.affirmative.enabled -or
                                $inquiry.negative.visible -or [string]::IsNullOrWhiteSpace([string]$inquiry.token)) {
                                throw 'The fresh Native state did not expose the expected one-button, affirmative-only Map YesNoInquiry.'
                            }
                            $storyModeNativeInquiryBeforeDay = [double]$storyModeNativeLeavePostActionSnapshot.campaignDay
                            Write-StoryModeCaptureEvent 'native-map-inquiry-visible' 'state' 'observed' 'MapState' ([string]$storyModeNativeLeavePostActionSnapshot.context.menuId)
                            $responseCommandId = 'fresh-storymode-inquiry-response-' + [Guid]::NewGuid().ToString('N')
                            $storyModeNativeInquiryResponseCommandId = $responseCommandId
                            $testSession = [ordered]@{ protocolVersion = 1; processId = [int]$bannerlordPid; startedUtc = (Get-Date).ToUniversalTime().ToString('O'); harnessNativeOnly = $true }
                            $sessionBytes = [Text.UTF8Encoding]::new($false).GetBytes(($testSession | ConvertTo-Json -Compress -Depth 4))
                            $sessionStream = [IO.File]::Open($agentSessionPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                            try { $sessionStream.Write($sessionBytes, 0, $sessionBytes.Length); $sessionStream.Flush($true) }
                            finally { $sessionStream.Dispose() }
                            $storyModeNativeInquiryTestSessionCreated = $true
                            $response = Invoke-FreshCampaignAgentCli 'respondInquiry' @(
                                '-InquiryToken', [string]$inquiry.token,
                                '-InquiryChoice', 'affirmative',
                                '-CommandId', $responseCommandId
                            ) -CommandTimeout 30
                            $storyModeNativeInquiryResponseRequested = $true
                            $storyModeNativeInquiryResponseReceipt = [ordered]@{
                                status = [string]$response.status
                                action = [string]$response.action
                                data = $response.data
                            }
                            if ($response.status -ne 'completed' -or $response.action -ne 'respondInquiry' -or
                                $response.data.choice -ne 'affirmative' -or $response.data.nativeViewModelHandler -ne 'ExecuteAffirmativeAction') {
                                throw 'Native respondInquiry did not report the expected affirmative SingleQueryPopUpVM callback.'
                            }
                            Write-StoryModeCaptureEvent 'native-map-inquiry-affirmative-response' 'respondInquiry' 'completed' 'MapState' ''
                            $storyModeNativeInquiryStateCommandId = "$responseCommandId-after"
                            $after = Invoke-FreshCampaignAgentCli 'state' @('-CommandId', $storyModeNativeInquiryStateCommandId) -CommandTimeout 15
                            $storyModeNativeInquiryStateAfterResponse = $after.state
                            $storyModeNativeInquiryAfterDay = [double]$after.campaignDay
                            if ($after.status -ne 'completed' -or
                                $after.state.context.gameState -ne 'MapState' -or
                                $after.state.context.inquiryOpen -or $after.state.context.inquiry -or
                                -not @($after.state.quests | Where-Object { $_.id -eq 'rebuild_player_clan_storymode_quest' }).Count -or
                                [Math]::Abs($storyModeNativeInquiryAfterDay - $storyModeNativeInquiryBeforeDay) -gt 0.001 -or
                                $after.timeControlMode -ne 'Stop') {
                                throw 'After affirmative response, Native state did not confirm a closed inquiry, active EYC, unchanged Campaign day and stopped clock.'
                            }
                            $storyModeNativeInquiryResponseVerified = $true
                            Write-StoryModeCaptureEvent 'native-map-inquiry-closed' 'state' 'verified' 'MapState' ''
                        }
                    }
                    catch {
                        if ($StoryModeNativeInquiryResponseEvaluation) {
                            $storyModeNativeInquiryResponseFailure = $_.Exception.Message
                            if ($inquiry -and -not [string]::IsNullOrWhiteSpace([string]$inquiry.token)) {
                                $storyModeNativeInquiryResponseFailure = $storyModeNativeInquiryResponseFailure.Replace([string]$inquiry.token, '[redacted-token]')
                            }
                        }
                        $harnessFailureObserved = $true
                    }
                }
            }
        }
        $startRequested = $startRequested -or [bool]($newLines -match "pid=$bannerlordPid\|fresh-campaign-start-requested\|save=none\|gameMode=sandbox$|pid=$bannerlordPid\|fresh-campaign-start-requested\|save=none\|gameMode=storymode\|entry=StoryModeNewGame$")
        $introSkippedObserved = $introSkippedObserved -or [bool]($newLines -match 'fresh-campaign-intro-skipped\|via=native-video-completion\|mode=harness$')
        $harnessFailureObserved = $harnessFailureObserved -or [bool]($newLines -match 'fresh-campaign-failed\||fresh-storymode-e2e-failed\|')
        $campaignSaveRequested = $campaignSaveRequested -or [bool]($newLines -match 'campaign-save-requested\|')
        $disposableSaveRequested = $disposableSaveRequested -or [bool]($newLines -match "fresh-campaign-disposable-save-requested\|name=$([regex]::Escape($freshCampaignSaveName))\|via=[^|]+$")
        $disposableSaveCompleted = $disposableSaveCompleted -or [bool]($newLines -match "fresh-campaign-disposable-save-complete\|name=$([regex]::Escape($freshCampaignSaveName))\|successful=True$")
        $disposableSaveFailed = $disposableSaveFailed -or [bool]($newLines -match "fresh-campaign-disposable-save-complete\|name=$([regex]::Escape($freshCampaignSaveName))\|successful=False$")
        $disposableSaveSuccessful = $disposableSaveSuccessful -or $disposableSaveCompleted
        $disposableSaveOwned = $disposableSaveOwned -or $disposableSaveRequested
        $disposableSaveSuccessful = $disposableSaveSuccessful -or $disposableSaveCompleted
        if ($disposableSaveRequested) { $disposableSaveOwned = $true }
        foreach ($saveCheckLine in $newLines) {
            if ($StoryModeEycPersistentSeed -and $saveCheckLine -match "fresh-campaign-disposable-save-time-check\|name=$([regex]::Escape($freshCampaignSaveName))\|campaignDayBefore=([^|]+)\|campaignDayAfter=([^|]+)\|timeControlModeBefore=([^|]+)\|timeControlModeAfter=([^|]+)\|campaignInstanceId=([^|]*)$") {
                $persistentStoryModeSaveTimeCheck = [ordered]@{ CampaignDayBefore=$Matches[1]; CampaignDayAfter=$Matches[2]; TimeControlModeBefore=$Matches[3]; TimeControlModeAfter=$Matches[4]; CampaignInstanceId=$Matches[5] }
            }
        }
        foreach ($line in $newLines) {
            if ($line -match 'fresh-campaign-stage\|index=(\d+)') { [void]$stageIndices.Add([int]$Matches[1]) }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-training-field-exit\|status=mission-ended\|via=brother-dialogue$') {
                $storyModeTrainingFieldExitPath = 'brother-dialogue'
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-training-field-exit\|status=native-leave-area-fallback-started\|via=NativeTabLeaveAreaFallback\|holdSeconds=([0-9.]+)\|clock=([^|]+)$') {
                $storyModeTrainingFieldExitPath = 'long-Tab-Native-Leave-Area-fallback'
                Write-StoryModeCaptureEvent 'training-field-long-tab-fallback-started' 'missionLeave' 'nativeInputHold' 'MissionState' 'training_field'
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-training-field-exit\|status=post-confirmation-dialogue-advanced\|via=NativeConversationManager$') {
                Write-StoryModeCaptureEvent 'tutorial-skip-dialogue-advanced' 'dialogueContinue' 'completed' 'MissionState' 'training_field'
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-training-field-exit\|status=native-leave-area-ended-mission\|via=NativeTabLeaveAreaFallback$') {
                Write-StoryModeCaptureEvent 'training-field-long-tab-fallback-ended-mission' 'missionLeave' 'completed' 'MapState' 'training_field_menu'
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-tutorial-skip\|status=original-brother-conversation-started$') {
                Write-StoryModeCaptureEvent 'brother-conversation-started' 'dialogueStart' 'completed' 'MissionState' 'training_field'
            }
            if ($line -match 'fresh-campaign-background-selected\|menu=narrative_adulthood_menu\|option=adulthood_defeated_enemy_option$') { $backgroundChoiceObserved = $true }
            if ($line -match 'fresh-campaign-character-creation-complete\|renown=([0-9.]+)\|tier=([^|]+)\|clock=([^|]+)\|mapState=([^|]+)$') {
                $creationCompleted = $true
                $renown = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
                $clock = $Matches[3]
                $mapState = $Matches[4]
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-tutorial-skip\|status=original-skip-selected\|option=player_answer_skip_tutorial$') {
                $storyModeTutorialSkipSelected = $true
                Write-StoryModeCaptureEvent 'tutorial-skip-selected' 'dialogueSelect' 'completed' 'MissionState' 'training_field'
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-tutorial-skip\|status=original-confirmation-selected\|option=end_tutorial_yes$') {
                $storyModeTutorialSkipConfirmed = $true
                if (-not $storyModeTutorialSkipConfirmedAt) { $storyModeTutorialSkipConfirmedAt = Get-Date }
                Write-StoryModeCaptureEvent 'tutorial-skip-confirmed' 'dialogueSelect' 'completed' 'MissionState' 'training_field'
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-post-skip-map-ready\|gameState=MapState\|menuId=([^|]*)\|settlement=([^|]*)\|eycActive=(True|False)$') {
                $storyModeMapReadyObserved = $true
                $storyModeMapMenuId = if ($Matches[1] -eq 'none') { $null } else { [string]$Matches[1] }
                $storyModeMapSettlementId = if ($Matches[2] -eq 'none') { $null } else { [string]$Matches[2] }
                $mapState = 'MapState'
                Write-StoryModeCaptureEvent 'campaign-map-after-tutorial-skip' 'mapStateObserved' 'completed' 'MapState' ([string]$Matches[1])
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-post-skip-map-snapshot\|json=(\{.*\})$') {
                try {
                    if (-not $storyModeFirstMapSnapshotPath) { throw 'Harness temp path is unavailable for the post-skip MapState observation.' }
                    [IO.File]::WriteAllBytes($storyModeFirstMapSnapshotPath, [Text.Encoding]::UTF8.GetBytes($Matches[1]))
                }
                catch { $harnessFailureObserved = $true }
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-post-skip-map-settled\|gameState=MapState\|menuId=([^|]*)\|settlement=([^|]*)\|eycActive=(True|False)$') {
                $storyModeMapSettledObserved = $true
                $mapState = 'MapState'
                Write-StoryModeCaptureEvent 'campaign-map-after-tutorial-skip-settled' 'captureFrame' 'completed' 'MapState' ([string]$Matches[1])
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-e2e-ready\|quest=rebuild_player_clan_storymode_quest\|mapState=MapState\|renown=([0-9.]+)\|campaignDay=([0-9.]+)$') {
                $storyModeEycReadyObserved = $true
                if (-not $storyModeTrainingFieldExitPath) { $storyModeTrainingFieldExitPath = 'brother-dialogue-path-no-tab-fallback' }
                $renown = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
                $mapState = 'MapState'
                $issueConversationProbeStatus = 'skipped:storymode-setup'
                Write-StoryModeCaptureEvent 'original-eyc-active' 'questActivationObserved' 'completed' 'MapState' ''
            }
            if ($line -match '\|fresh-campaign-snapshot\|json=(\{.*\})$') {
                try {
                    if (-not $snapshotArtifactPath) { throw 'Harness temp directory is not set.' }
                    [IO.File]::WriteAllBytes($snapshotArtifactPath, [Text.Encoding]::UTF8.GetBytes($Matches[1]))
                    $initialSnapshotCaptured = $true
                }
                catch { $harnessFailureObserved = $true }
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-e2e-snapshot\|json=(\{.*\})$') {
                try {
                    if (-not $snapshotArtifactPath) { throw 'Harness temp directory is not set.' }
                    [IO.File]::WriteAllBytes($snapshotArtifactPath, [Text.Encoding]::UTF8.GetBytes($Matches[1]))
                    $initialSnapshotCaptured = $true
                }
                catch { $harnessFailureObserved = $true }
            }
            if ($StoryModeEycSetup -and $line -match 'fresh-storymode-frame-captured\|name=([^|]+)\|file=([^|]+)\|gameState=([^|]+)\|menuId=(.*)$') {
                $frameName = [string]$Matches[1]
                $frameFile = [string]$Matches[2]
                $framePath = Join-Path $env:CHRONICLE_HARNESS_TEMP $frameFile
                $frameDeadline = (Get-Date).AddSeconds(5)
                while (-not (Test-Path -LiteralPath $framePath -PathType Leaf) -and (Get-Date) -lt $frameDeadline) { Start-Sleep -Milliseconds 100 }
                if (Test-Path -LiteralPath $framePath -PathType Leaf) {
                    $finalFramePath = Join-Path $storyModeEvidenceRoot $frameFile
                    if (Test-Path -LiteralPath $finalFramePath) { throw "Fresh StoryMode frame already exists: $frameFile" }
                    Move-Item -LiteralPath $framePath -Destination $finalFramePath
                    [void]$storyModeNativeFrameNames.Add($frameName)
                    $storyModeNativeFrameHashes[$frameName] = (Get-FileHash -LiteralPath $finalFramePath -Algorithm SHA256).Hash
                    if ($frameName -eq 'eyc-map-render-settled') {
                        $storyModeRenderSettledObserved = $true
                        Write-StoryModeCaptureEvent 'map-render-settled' 'captureFrame' 'completed' 'MapState' ''
                    }
                    if ($frameName -eq 'campaign-map-after-tutorial-skip-settled') {
                        $storyModeMapSettledObserved = $true
                    }
                }
                else { $harnessFailureObserved = $true }
            }
            if ($line -match 'fresh-campaign-visible-issues\|settlements=(.*)$') {
                $visibleIssuePoolObserved = $true
                $visibleIssueTypes = $Matches[1]
            }
            if ($line -match 'fresh-campaign-issue-probe\|status=skipped\|reason=([^|]+)$') {
                $issueConversationProbeStatus = "skipped:$($Matches[1])"
            }
            if ($line -match 'fresh-campaign-issue-probe\|status=(opened|failed)\|settlement=([^|]+)\|heroId=([^|]+)\|issueType=([^|]+)\|issueOfferOption=(True|False)\|issueBriefReached=(True|False)\|issueOfferDenied=(True|False)\|questAcceptanceAvailable=(True|False)\|clockBefore=([^|]+)\|clockAfter=([^|]+)\|options=(.*)$') {
                $issueConversationProbeStatus = $Matches[1]
                $issueConversationOfferOption = $Matches[5] -eq 'True'
                $issueConversationBriefReached = $Matches[6] -eq 'True'
                $issueConversationOfferDenied = $Matches[7] -eq 'True'
                $issueQuestAcceptanceAvailable = $Matches[8] -eq 'True'
                $issueConversationClockBefore = $Matches[9]
                $issueConversationClockAfter = $Matches[10]
                $issueConversationOptions = if ($Matches[11]) { @($Matches[11] -split ',') } else { @() }
            }
        }

        $rglText = ''
        if ($bannerlordPid -and (Test-Path -LiteralPath $rglLog)) {
            $rglText = [string](Get-Content -LiteralPath $rglLog -Raw)
            $crashDetected = $crashDetected -or ($rglText -match 'Unhandled Exception|Crash occurred|ExceptionCode:')
        }
        if ($bannerlordPid -and (Test-Path -LiteralPath $watchdogLog)) {
            $watchdogText = [string](Get-Content -LiteralPath $watchdogLog -Raw)
            $crashDetected = $crashDetected -or ($watchdogText -match 'Crash occurred|ExceptionCode:')
        }
        if ($crashDetected -and $bannerlordPid -and -not $crashModulesCaptured) {
            $crashModulesCaptured = $true
            try {
                $targetProcess = Get-Process -Id $bannerlordPid -ErrorAction Stop
                $loadedModules = @($targetProcess.Modules)
                $faultMatch = [regex]::Match($rglText, '(?i)Unhandled Exception Code 0x[0-9a-f]+ at (?:adress|address) 0x([0-9a-f]+)')
                [UInt64]$faultValue = 0
                if ($faultMatch.Success) {
                    $faultValue = [Convert]::ToUInt64($faultMatch.Groups[1].Value, 16)
                    $crashFaultAddress = '0x' + $faultMatch.Groups[1].Value.ToUpperInvariant()
                }
                foreach ($module in $loadedModules) {
                    $baseValue = [UInt64]$module.BaseAddress.ToInt64()
                    $sizeValue = [UInt64]$module.ModuleMemorySize
                    $version = ''
                    try { $version = [string]$module.FileVersionInfo.FileVersion } catch { }
                    $crashModuleInventory += [ordered]@{ name = [string]$module.ModuleName; baseAddress = ('0x{0:X}' -f $baseValue); size = $sizeValue; fileVersion = $version }
                    if ($faultMatch.Success -and $faultValue -ge $baseValue -and $faultValue -lt ($baseValue + $sizeValue)) {
                        $crashFaultModule = [string]$module.ModuleName
                    }
                }
            }
            catch { $crashModuleCaptureError = $_.Exception.Message }
        }
        if ($crashDetected -and -not $crashWindowCaptureAttempted -and $bannerlordPid -and $candidate) {
            $crashWindowCaptureAttempted = $true
            if (-not [string]::IsNullOrWhiteSpace($env:CHRONICLE_HARNESS_TEMP)) {
                try {
                    . (Join-Path $PSScriptRoot 'HarnessVideoCapture.ps1')
                    $crashWindowCapturePath = Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashObserved-$bannerlordPid.mp4"
                    $crashWindowCapture = Start-ChronicleWindowVideoCapture -ProcessId $bannerlordPid -OutputPath $crashWindowCapturePath -FrameRate 10
                    $crashWindowEventTracePath = Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashObserved-$bannerlordPid-events.jsonl"
                    $crashObservedEvent = [ordered]@{ event = 'native-crash-signature'; action = 'crashObserved'; commandId = "crash-$bannerlordPid-observed"; gameState = 'StartupCrash'; menuId = ''; partyScreenMode = ''; inventoryMode = ''; utc = (Get-Date).ToUniversalTime().ToString('O'); offsetMilliseconds = 1000 }
                    [IO.File]::WriteAllText($crashWindowEventTracePath, (ConvertTo-Json -InputObject $crashObservedEvent -Compress) + [Environment]::NewLine, [Text.Encoding]::UTF8)
                    $crashWindowCaptureUntil = (Get-Date).AddSeconds(2.2)
                }
                catch { $crashWindowCaptureError = $_.Exception.Message }
            }
            else { $crashWindowCaptureError = 'Harness temp directory is unavailable for crash capture.' }
        }

        if ($StoryModeEycLiveModelEvaluation -and $storyModeMapSettledObserved -and $storyModeVideoCapture -and $storyModeVideoCaptureActive) {
            try {
                Write-StoryModeCaptureEvent 'capture-end-after-map-settled' 'capture' 'completed' 'MapState' ([string]$storyModeMapMenuId)
                $storyModeVideoCaptureResult = Stop-ChronicleWindowVideoCapture -Capture $storyModeVideoCapture -ContactSheetPath $storyModeVideoContactPath -EventTracePath $storyModeVideoEventsPath
                $storyModeVideoCaptureActive = $false
                $storyModeVideoCapture = $null
            }
            catch {
                $storyModeVideoCaptureError = $_.Exception.Message
                $storyModeVideoCaptureRetained = Test-Path -LiteralPath $storyModeVideoPath
                $storyModeVideoCaptureActive = $false
            }
        }
        $storyModeTakeoverMapReady = if ($StoryModeEycLiveModelEvaluation) { $storyModeMapReadyObserved -and $storyModeMapSettledObserved } else { $storyModeEycReadyObserved -and $storyModeRenderSettledObserved }
        $creationReady = if ($StoryModeEycSetup) {
            $creationCompleted -and $initialSnapshotCaptured -and $storyModeTutorialSkipSelected -and $storyModeTutorialSkipConfirmed -and $storyModeTakeoverMapReady -and (-not $StoryModeNativeMenuLeaveEvaluation -or $storyModeNativeLeaveVerified)
        } else {
            $creationCompleted -and $initialSnapshotCaptured -and $issueConversationProbeStatus -ne 'not-observed'
        }
        if ($StoryModeEycPersistentSeed -and $creationReady -and $storyModeEycReadyObserved -and -not $persistentStoryModeSaveReadySignaled) {
            if (Test-Path -LiteralPath $persistentStoryModeSaveReadyFile) { throw 'The unique persistent StoryMode save-ready signal already exists.' }
            $persistentStoryModeSaveOwned = $true
            [IO.File]::WriteAllText($persistentStoryModeSaveReadyFile, 'Native MapState ready for disposable SaveAs', [Text.UTF8Encoding]::new($false))
            $persistentStoryModeSaveReadySignaled = $true
        }
        $saveReady = -not $ValidateRecruitmentProgression -or $disposableSaveCompleted
        $storyModeAgentReadyForExit = -not $StoryModeEycLiveModelEvaluation -or (($storyModeAgentHostStarted -and $storyModeAgentHostReady -and -not [string]::IsNullOrWhiteSpace($storyModeAgentHostTerminalState)) -or ($storyModeAgentHostStartRequested -and $storyModeAgentHostTerminalState -eq 'Failed'))
        if ($StoryModeEycLiveModelEvaluation -and $storyModeTutorialSkipConfirmedAt -and -not $storyModeAgentHostStartRequested -and
            (Get-Date) -ge $storyModeTutorialSkipConfirmedAt.AddSeconds(180)) {
            $storyModeStartupFailure = 'Native tutorial skip was confirmed, but no Agent Host start request was observed within 180 seconds.'
            $storyModeAgentHostTerminalState = 'Failed'
            $storyModeAgentHostTerminalDetail = $storyModeStartupFailure
            $harnessFailureObserved = $true
            ChronicleDiagnostics.Write('fresh-storymode-startup-timeout|stage=host-start-request|seconds=180')
        }
        elseif ($StoryModeEycLiveModelEvaluation -and $storyModeAgentHostStartRequestedAt -and -not $storyModeAgentHostReady -and
            (Get-Date) -ge $storyModeAgentHostStartRequestedAt.AddSeconds(90)) {
            $storyModeStartupFailure = 'The Agent Host start was requested, but its ready handshake was not observed within 90 seconds.'
            $storyModeAgentHostTerminalState = 'Failed'
            $storyModeAgentHostTerminalDetail = $storyModeStartupFailure
            $harnessFailureObserved = $true
            ChronicleDiagnostics.Write('fresh-storymode-startup-timeout|stage=host-ready|seconds=90')
        }
        $crashCaptureGraceActive = $crashWindowCapture -and $crashWindowCaptureUntil -and (Get-Date) -lt $crashWindowCaptureUntil
        if (($creationReady -and $saveReady -and $storyModeAgentReadyForExit) -or (($crashDetected -or $harnessFailureObserved) -and -not $crashCaptureGraceActive)) { break }
        if (-not (Get-Process -Id $launcherProcess.Id -ErrorAction SilentlyContinue) -and -not (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 300
    }

    if ($StoryModeEycPersistentSeed) {
        if (-not $creationReady -or -not $storyModeEycReadyObserved) {
            $hostDetail = [string]$storyModeAgentHostTerminalDetail
            if ($hostDetail.Length -gt 500) { $hostDetail = $hostDetail.Substring(0,500) + '...[truncated]' }
            throw "Persistent EYC seed save requires the original Tutorial skip, naturally active Quest and stable Native Campaign Map before saving. creationReady=$creationReady; eycActive=$storyModeEycReadyObserved; tutorialSkip=$storyModeTutorialSkipConfirmed; mapReady=$storyModeTakeoverMapReady; hostStarted=$storyModeAgentHostStarted; hostReady=$storyModeAgentHostReady; hostStartRequested=$storyModeAgentHostStartRequested; hostTerminal=$storyModeAgentHostTerminalState; hostDetail=$hostDetail."
        }
        if (-not $persistentStoryModeSaveReadySignaled) {
            throw 'The stable Native StoryMode MapState was observed, but no persistent SaveAs readiness signal was issued.'
        }
        $saveDeadline = (Get-Date).AddSeconds([Math]::Max(60, [Math]::Min($TimeoutSeconds, 180)))
        while ((-not $disposableSaveCompleted -or $null -eq $persistentStoryModeSaveTimeCheck) -and -not $disposableSaveFailed -and (Get-Date) -lt $saveDeadline) {
            $allDiagnosticLines = if (Test-Path -LiteralPath $diagnosticLog -PathType Leaf) { @(Get-Content -LiteralPath $diagnosticLog -Encoding UTF8) } else { @() }
            $saveDiagnosticLines = if ($allDiagnosticLines.Count -gt $diagnosticStartLineCount) { @($allDiagnosticLines[$diagnosticStartLineCount..($allDiagnosticLines.Count - 1)]) } else { @() }
            $diagnosticStartLineCount = $allDiagnosticLines.Count
            foreach ($saveLine in $saveDiagnosticLines) {
                if ($saveLine -match "fresh-campaign-disposable-save-requested\|name=$([regex]::Escape($freshCampaignSaveName))\|via=[^|]+$") { $disposableSaveRequested = $true }
                if ($saveLine -match "fresh-campaign-disposable-save-complete\|name=$([regex]::Escape($freshCampaignSaveName))\|successful=True$") { $disposableSaveCompleted = $true }
                if ($saveLine -match "fresh-campaign-disposable-save-complete\|name=$([regex]::Escape($freshCampaignSaveName))\|successful=False$") { $disposableSaveFailed = $true }
                if ($saveLine -match "fresh-campaign-disposable-save-time-check\|name=$([regex]::Escape($freshCampaignSaveName))\|campaignDayBefore=([^|]+)\|campaignDayAfter=([^|]+)\|timeControlModeBefore=([^|]+)\|timeControlModeAfter=([^|]+)\|campaignInstanceId=([^|]*)$") {
                    $persistentStoryModeSaveTimeCheck = [ordered]@{ CampaignDayBefore=[double]$Matches[1]; CampaignDayAfter=[double]$Matches[2]; TimeControlModeBefore=$Matches[3]; TimeControlModeAfter=$Matches[4]; CampaignInstanceId=$Matches[5] }
                }
            }
            $disposableSaveOwned = $disposableSaveOwned -or $disposableSaveRequested
            $disposableSaveSuccessful = $disposableSaveSuccessful -or $disposableSaveCompleted
            if ($disposableSaveFailed -or ($disposableSaveCompleted -and $null -ne $persistentStoryModeSaveTimeCheck)) { break }
            Start-Sleep -Milliseconds 250
        }
        if (-not $disposableSaveRequested -or -not $disposableSaveCompleted -or $disposableSaveFailed) {
            throw 'Native SaveHandler did not confirm SaveAs for the stable MapState before the persistent seed timeout.'
        }
        if (-not (Test-Path -LiteralPath $persistentStoryModeSavePath -PathType Leaf) -or (Get-Item -LiteralPath $persistentStoryModeSavePath).Length -lt 4096) {
            throw 'Native SaveAs returned completed, but the persistent StoryMode fixture file is missing or incomplete.'
        }
        $persistentStoryModeSaveHash = (Get-FileHash -LiteralPath $persistentStoryModeSavePath -Algorithm SHA256).Hash
        $campaignSaveRequested = $true
        if ($null -eq $persistentStoryModeSaveTimeCheck -or [string]::IsNullOrWhiteSpace([string]$persistentStoryModeSaveTimeCheck.CampaignInstanceId) -or
            [Math]::Abs([double]$persistentStoryModeSaveTimeCheck.CampaignDayAfter - [double]$persistentStoryModeSaveTimeCheck.CampaignDayBefore) -gt 0.001 -or
            [string]$persistentStoryModeSaveTimeCheck.TimeControlModeBefore -cne [string]$persistentStoryModeSaveTimeCheck.TimeControlModeAfter) {
            throw 'Native SaveAs completion did not preserve Campaign time/mode and Campaign instance identity.'
        }
        $campaignInstanceId = [string]$persistentStoryModeSaveTimeCheck.CampaignInstanceId
        $persistentStoryModeSaveCompleted = $true
    }

}
finally {
    if ($storyModeVideoCapture) {
        try {
            Write-StoryModeCaptureEvent 'capture-end' 'capture' 'completed' $mapState ''
            $storyModeVideoCaptureResult = Stop-ChronicleWindowVideoCapture -Capture $storyModeVideoCapture -ContactSheetPath $storyModeVideoContactPath -EventTracePath $storyModeVideoEventsPath
            $storyModeVideoCaptureActive = $false
        }
        catch {
            $storyModeVideoCaptureError = $_.Exception.Message
            $storyModeVideoCaptureRetained = Test-Path -LiteralPath $storyModeVideoPath
            $storyModeVideoCaptureActive = $false
        }
    }
    if ($crashWindowCapture) {
        $crashContactSheetPath = Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashReport-$bannerlordPid-contact.jpg"
        try {
            $crashWindowCaptureResult = Stop-ChronicleWindowVideoCapture -Capture $crashWindowCapture -ContactSheetPath $crashContactSheetPath -EventTracePath $crashWindowEventTracePath
        }
        catch {
            $crashWindowCaptureError = $_.Exception.Message
            $crashWindowCaptureRetained = Test-Path -LiteralPath $crashWindowCapture.OutputPath
        }
    }
    $descendants = @(Get-DescendantProcessIds -ParentId $launcherProcess.Id)
    foreach ($processId in @($descendants + $bannerlordPid + $launcherProcess.Id) | Where-Object { $_ } | Select-Object -Unique) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
    Set-SafeExitMarker
    if ($ValidateRecruitmentProgression) {
        if (Test-Path -LiteralPath $agentSessionPath) {
            try {
                $sessionNow = Get-Content -LiteralPath $agentSessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($sessionNow.processId -eq $bannerlordPid) { Remove-Item -LiteralPath $agentSessionPath -Force -ErrorAction SilentlyContinue }
            } catch { }
        }
        if ($previousSessionExisted) { [IO.File]::WriteAllBytes($agentSessionPath, $previousSessionBytes) }
        if (Test-Path -LiteralPath $agentCommandPath) {
            try { if ((Get-Content -LiteralPath $agentCommandPath -Raw -Encoding UTF8 | ConvertFrom-Json).id -like "$progressionCommandPrefix*") { Remove-Item -LiteralPath $agentCommandPath -Force } } catch { }
        }
        if (Test-Path -LiteralPath $agentResponseRoot) {
            Get-ChildItem -LiteralPath $agentResponseRoot -File -Filter "$progressionCommandPrefix*.json" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

$cleanupDeadline = (Get-Date).AddSeconds(15)
do {
    $remainingBannerlordProcesses = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    if ($remainingBannerlordProcesses.Count -eq 0) { break }
    Start-Sleep -Milliseconds 200
} while ((Get-Date) -lt $cleanupDeadline)

if ($autoSaveSettingGuard) {
    try {
        $autoSaveSettingRestoration = Restore-ChronicleHarnessAutoSaveSetting
        if (-not $autoSaveSettingRestoration.Restored) {
            $autoSaveSettingRestorationError = "Autosave setting restoration was not completed: $($autoSaveSettingRestoration.Status)"
            $harnessFailureObserved = $true
        }
        $autoSaveIntervalAfter = Get-ChronicleBannerlordAutoSaveInterval -LiteralPath $bannerlordConfigPath
        if ($autoSaveIntervalAfter -ne $autoSaveIntervalBefore) {
            $autoSaveSettingRestorationError = "Bannerlord AutoSaveInterval did not return to its pre-test value ($autoSaveIntervalBefore)."
            $harnessFailureObserved = $true
        }
    }
    catch {
        $autoSaveSettingRestorationError = $_.Exception.Message
        $harnessFailureObserved = $true
    }
}
if ($gameSoundSettingGuard) {
    try {
        $gameSoundSettingRestoration = Restore-ChronicleHarnessGameSound
        if (-not $gameSoundSettingRestoration.Restored) {
            $gameSoundSettingRestorationError = "Game sound setting restoration was not completed: $($gameSoundSettingRestoration.Status)"
            $harnessFailureObserved = $true
        }
        $gameSoundDisabledAfter = Get-ChronicleBannerlordSoundDisabled -LiteralPath $engineConfig
        if ($gameSoundDisabledAfter -ne $gameSoundDisabledBefore) {
            $gameSoundSettingRestorationError = "Bannerlord disable_sound did not return to its pre-test value ($gameSoundDisabledBefore)."
            $harnessFailureObserved = $true
        }
    }
    catch {
        $gameSoundSettingRestorationError = $_.Exception.Message
        $harnessFailureObserved = $true
    }
}
if ($bannerlordPid -and $rglLog -and (Test-Path -LiteralPath $rglLog -PathType Leaf)) {
    try { $nativeAutoSaveDetected = [string](Get-Content -LiteralPath $rglLog -Raw -Encoding UTF8) -match 'AutoSaveCurrentGame' }
    catch { $nativeAutoSaveDetected = $true }
}

if ($ValidateRecruitmentProgression) {
    try {
        if (-not $gameStarted) { throw "FreshCampaign process did not reach game-start; crashDetected=$crashDetected window='$crashWindowTitle' startupDialog='$startupDialogFailure'." }
        if (-not $creationCompleted -or -not $initialSnapshotCaptured) { throw "FreshCampaign did not reach an observed character-created MapState; crashDetected=$crashDetected window='$crashWindowTitle'." }
        if (-not $disposableSaveRequested) { throw 'FreshCampaign character creation completed but did not request the uniquely named disposable save.' }
        if (-not $disposableSaveCompleted -or -not $disposableSaveSuccessful) { throw 'Fresh campaign did not confirm completion of its isolated disposable save.' }
        if (-not (Test-Path -LiteralPath $progressionSavePath) -or (Get-Item -LiteralPath $progressionSavePath).Length -lt 4096) { throw 'Fresh campaign disposable save is missing or incomplete.' }
        $disposableSaveOwned = $true

        $load = Invoke-FreshCampaignAgentCli 'load' @('-SaveName', $progressionSaveName) -CommandTimeout $TimeoutSeconds
        if ($load.status -ne 'completed' -or -not $load.session.processId) { throw 'Standard Agent CLI could not load the fresh-created disposable save.' }
        $loadedState = Invoke-FreshCampaignAgentCli 'state' @('-CommandId', "$progressionCommandPrefix-observe-start")
        $checkpointIdentity = Invoke-FreshCampaignAgentCli 'agentCheckpointGet' @('-CommandId', "$progressionCommandPrefix-campaign-identity")
        if ($checkpointIdentity.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$checkpointIdentity.data.campaignInstanceId)) { throw 'Native Campaign did not expose its Chronicle campaign-instance identifier for the fresh-start baseline.' }
        $campaignInstanceId = [string]$checkpointIdentity.data.campaignInstanceId
        if ($loadedState.state.economy.renown -ne 20 -or $loadedState.state.party.members -ne 1 -or $loadedState.state.economy.gold -ne 1000) { throw 'Reloaded fresh save did not preserve the expected 20-Renown/solo/1000-gold baseline.' }
        if ($RealModelRecruitment) {
            $identityLoadStartupDialogs = @($load.session.startupDialogReceipts)
            $identityLoadStop = Invoke-FreshCampaignAgentCli 'stop' @('-CommandId', "$progressionCommandPrefix-identity-stop") -CommandTimeout 30
            if ($identityLoadStop.status -ne 'completed' -or -not $identityLoadStop.processStopped) { throw 'Fresh-Campaign identity read did not stop its temporary Agent session before the live-model runtime.' }
            $modelName = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'Process')
            if ([string]::IsNullOrWhiteSpace($modelName)) { $modelName = [string][Environment]::GetEnvironmentVariable('CHRONICLE_LLM_MODEL', 'User') }
            if ([string]::IsNullOrWhiteSpace($modelName)) { throw 'Real-model fresh-Campaign evaluation requires a locally configured model name; credentials are never printed.' }
            $modelRunStartedUtc = [DateTime]::UtcNow
            $modelOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $agentLiveModelLoop -LoadSaveName $progressionSaveName -RecruitmentLoop -FrameRate 10 -TimeoutSeconds $TimeoutSeconds 2>&1 | Out-String
            $modelExitCode = $LASTEXITCODE
            $modelRunWallClockSeconds = ([DateTime]::UtcNow - $modelRunStartedUtc).TotalSeconds
            try { $liveModelResult = $modelOutput | ConvertFrom-Json }
            catch { throw "Fresh-Campaign real-model loop did not return structured JSON (exit=$modelExitCode): $modelOutput" }
            if ($modelExitCode -ne 0 -or -not $liveModelResult.Passed) {
                throw "Fresh-Campaign real-model loop failed (exit=$modelExitCode): $($liveModelResult.Failure)"
            }
            $liveTrace = @($liveModelResult.Trace.Trace)
            $liveMoveSteps = @($liveTrace | Where-Object { $_.decision.action -eq 'move' -and $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' })
            $liveOfferSteps = @($liveTrace | Where-Object { $_.decision.action -eq 'recruitOptions' -and $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' })
            $liveRecruitSteps = @($liveTrace | Where-Object { $_.decision.action -eq 'recruit' -and $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' })
            if ($liveMoveSteps.Count -ne 1 -or $liveOfferSteps.Count -ne 1 -or $liveRecruitSteps.Count -ne 1) { throw 'Real-model fresh-Campaign result did not contain exactly one completed Native Move, offer read, and Recruit.' }
            $liveRecruitBefore = $liveRecruitSteps[0].observationBefore.state
            $liveRecruitAfter = $liveRecruitSteps[0].observationAfter.state
            $liveOfferReceipt = $liveOfferSteps[0].actionReceipt.data
            $selectedOffer = @($liveOfferReceipt.offers | Where-Object { $_.available -and [string]$_.ownerId -ceq [string]$liveRecruitSteps[0].decision.arguments.OwnerId -and [string]$_.troopId -ceq [string]$liveRecruitSteps[0].decision.arguments.TroopId -and [int]$_.slot -eq [int]$liveRecruitSteps[0].decision.arguments.VolunteerSlot -and [int]$_.cost -le [int]$liveRecruitBefore.economy.gold -and [int]$liveRecruitBefore.party.members -lt [int]$liveRecruitBefore.party.sizeLimit } | Select-Object -First 1)
            $recruitVerified = (
                $selectedOffer.Count -eq 1 -and
                [bool]$liveRecruitSteps[0].actionReceipt.data.verified -and
                [int]$liveRecruitAfter.party.members -eq ([int]$liveRecruitBefore.party.members + 1) -and
                ([int]$liveRecruitBefore.economy.gold - [int]$liveRecruitAfter.economy.gold) -eq [int]$selectedOffer[0].cost -and
                -not [bool]$liveRecruitSteps[0].decision.arguments.ConfirmPartySizeWarning
            )
            $initialModelObservation = $liveTrace[0].observationBefore
            $finalModelObservation = if ($liveTrace.Count -gt 0 -and $liveTrace[-1].observationAfter) { $liveTrace[-1].observationAfter } else { $null }
            $campaignDaysElapsed = if ($finalModelObservation) { [double]$finalModelObservation.campaignDay - [double]$initialModelObservation.campaignDay } else { $null }
            $preNativeRejectedDecisions = @($liveTrace | Where-Object { $_.control.kind -eq 'decision-rejected-before-native' }).Count
            $rejectedNativeActions = @($liveTrace | Where-Object { $_.actionAttempted -and -not $_.actionExecuted }).Count
            $captureEvidence = $liveModelResult.Trace.VisualEvidence
            $captureReceipt = $liveModelResult.Capture
            $recruitmentProgressionPassed = (
                [bool]$liveModelResult.Passed -and $recruitVerified -and
                [bool]$liveModelResult.FixtureUnchanged -and [bool]$liveModelResult.ProcessStopped -and
                $rejectedNativeActions -eq 0 -and $null -ne $campaignDaysElapsed -and $campaignDaysElapsed -le 0.1 -and
                [double]$captureEvidence.FrameCoverageRatio -ge 0.9 -and [bool]$captureReceipt.VideoRemovedAfterEvidence
            )
            $recruitmentProgression = [ordered]@{
                ProviderKind = [string]$liveModelResult.Trace.ProviderKind
                Model = $modelName
                DisposableSaveName = $progressionSaveName
                ChronicleCampaignInstanceId = $campaignInstanceId
                InitialRenown = [double]$initialModelObservation.state.economy.renown
                InitialMembers = [int]$initialModelObservation.state.party.members
                InitialGold = [int]$initialModelObservation.state.economy.gold
                InitialLocation = $initialModelObservation.state.location
                VisibleSafeSettlements = $initialModelObservation.state.nearbySettlements
                TargetSettlementId = [string]$liveModelResult.Trace.ChosenSettlementId
                TargetSource = [string]$liveModelResult.Trace.ChosenTargetSource
                MoveCount = $liveMoveSteps.Count
                RecruitmentCount = $liveRecruitSteps.Count
                RecruitmentOfferCount = @($liveOfferReceipt.offers).Count
                SelectedOffer = $selectedOffer[0]
                RecruitReceipt = $liveRecruitSteps[0].actionReceipt.data
                MembersAfter = [int]$liveRecruitAfter.party.members
                GoldAfter = [int]$liveRecruitAfter.economy.gold
                RenownAfter = [double]$liveRecruitAfter.economy.renown
                CampaignDaysElapsed = $campaignDaysElapsed
                WallClockSeconds = [Math]::Round($modelRunWallClockSeconds, 3)
                Decisions = $liveTrace.Count
                RecruitmentVerified = $recruitVerified
                PreNativeRejectedDecisions = $preNativeRejectedDecisions
                RejectedNativeActions = $rejectedNativeActions
                VisualCoverageRatio = [double]$captureEvidence.FrameCoverageRatio
                VideoRemovedAfterEvidence = [bool]$captureReceipt.VideoRemovedAfterEvidence
                RuntimeStartupDialogReceipts = @($liveModelResult.Trace.StartupDialogReceipts)
                StartupDialogReceipts = $identityLoadStartupDialogs + @($liveModelResult.Trace.StartupDialogReceipts)
                FixtureUnchanged = [bool]$liveModelResult.FixtureUnchanged
                ProcessStopped = [bool]$liveModelResult.ProcessStopped
                Passed = $recruitmentProgressionPassed
            }
            if (-not $recruitmentProgressionPassed) { throw 'Real-model fresh-Campaign candidate violated its predeclared result, no-rejection, time, video, fixture, or process-cleanup conditions.' }
        }
        else {
        $target = @($loadedState.state.nearbySettlements | Where-Object { -not $_.hostile -and $_.distance -gt 1.0 } | Sort-Object distance | Select-Object -First 1)
        if ($target.Count -ne 1) { throw 'No safe visible settlement exists for the recruitment progression step.' }
        $move = Invoke-FreshCampaignAgentCli 'move' @('-SettlementId', [string]$target[0].id, '-CommandId', "$progressionCommandPrefix-move")
        if ($move.status -ne 'completed' -or $move.state.location.targetSettlementId -ne $target[0].id) { throw 'Reloaded fresh campaign move did not target the selected settlement.' }
        $arrival = Wait-ForAgentSettlementArrival -CliPath $agentCli -SettlementId ([string]$target[0].id) -CommandPrefix "$progressionCommandPrefix-travel" -TimeoutSeconds $TimeoutSeconds
        if ($arrival.state.location.currentSettlementId -ne $target[0].id) { throw 'Reloaded fresh campaign failed to arrive at the recruitment settlement.' }

        $beforeRecruit = Invoke-FreshCampaignAgentCli 'state' @('-CommandId', "$progressionCommandPrefix-before-recruit")
        $previousProviderMode = $env:CHRONICLE_TEST_PROVIDER_MODE
        $env:CHRONICLE_TEST_PROVIDER_MODE = 'recruitment'
        try {
            $loopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $agentDecisionLoop -DecisionProviderPath $agentLoopProvider -MaxDecisions 2 -TimeoutSeconds ([Math]::Min(15, $TimeoutSeconds)) -CommandPrefix "$progressionCommandPrefix-loop" 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw "FreshCampaign recruitment decision loop failed: $loopOutput" }
            $loop = $loopOutput | ConvertFrom-Json
        }
        finally {
            if ($null -eq $previousProviderMode) { Remove-Item Env:CHRONICLE_TEST_PROVIDER_MODE -ErrorAction SilentlyContinue }
            else { $env:CHRONICLE_TEST_PROVIDER_MODE = $previousProviderMode }
        }
        $offer = @($loop.trace[0].actionReceipt.data.offers | Where-Object { $_.available -and $_.cost -le $beforeRecruit.state.economy.gold } | Sort-Object cost | Select-Object -First 1)
        if ($offer.Count -ne 1) { throw 'FreshCampaign RecruitmentVM exposed no affordable volunteer offer.' }
        $recruit = $loop.trace[1].actionReceipt
        $afterRecruit = $loop.trace[1].observationAfter
        $receiptForwarded = ($loop.trace[1].previousActionReceipt.commandId -eq $loop.trace[0].actionReceipt.commandId -and @($loop.trace[1].previousActionReceipt.data.offers).Count -gt 0)
        $stop = Invoke-FreshCampaignAgentCli 'stop' @('-CommandId', "$progressionCommandPrefix-stop") -CommandTimeout 30
        $recruitmentProgressionPassed = ($receiptForwarded -and $loop.trace[1].decision.action -eq 'recruit' -and $recruit.data.verified -and $afterRecruit.state.party.members -eq $beforeRecruit.state.party.members + 1 -and $afterRecruit.state.economy.gold -eq $beforeRecruit.state.economy.gold - $offer[0].cost -and $afterRecruit.state.economy.renown -eq 20 -and $stop.status -eq 'completed' -and $stop.processStopped)
        $recruitmentProgression = [ordered]@{
            ProviderKind = 'deterministic-test-only'
            DisposableSaveName = $progressionSaveName
            InitialRenown = $loadedState.state.economy.renown
            InitialMembers = $loadedState.state.party.members
            InitialGold = $loadedState.state.economy.gold
            Target = $target[0]
            MoveTimeBefore = $loadedState.timeControlMode
            MoveTimeAfter = $move.timeControlMode
            ArrivalTimeMode = $arrival.timeControlMode
            RecruitmentMenu = $beforeRecruit.state.context.menuId
            OfferCount = @($loop.trace[0].actionReceipt.data.offers).Count
            SelectedOffer = $offer[0]
            ReceiptForwarded = $receiptForwarded
            RecruitReceipt = $recruit.data
            MembersAfter = $afterRecruit.state.party.members
            GoldAfter = $afterRecruit.state.economy.gold
            RenownAfter = $afterRecruit.state.economy.renown
            ProcessStopped = $stop.processStopped
            Passed = $recruitmentProgressionPassed
        }
        }
    }
    catch {
        $activeGameProcess = Get-Process -Id $bannerlordPid -ErrorAction SilentlyContinue
        if ($activeGameProcess) {
            $crashWindowTitle = [string]$activeGameProcess.MainWindowTitle
            if ($crashWindowTitle -match '(?i)Crash Report|CrashReporter') { $crashDetected = $true }
        }
        if ([string]::IsNullOrWhiteSpace($recruitmentProgressionError)) { $recruitmentProgressionError = $_.Exception.ToString() }
        else { $recruitmentProgressionError = "$recruitmentProgressionError; validation: $($_.Exception.Message)" }
        $recruitmentProgressionPassed = $false
        $recruitmentProgression = [ordered]@{ ProviderKind = 'deterministic-test-only'; DisposableSaveName = $progressionSaveName; Passed = $false; Error = $recruitmentProgressionError }
        if (Test-Path -LiteralPath $agentSessionPath) {
            try {
                $sessionNow = Get-Content -LiteralPath $agentSessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if (Get-Process -Id $sessionNow.processId -ErrorAction SilentlyContinue) { Invoke-FreshCampaignAgentCli 'stop' @('-CommandId', "$progressionCommandPrefix-failure-stop") -CommandTimeout 30 | Out-Null }
            } catch { }
        }
    }
    finally {
        if ($previousSessionExisted) { [IO.File]::WriteAllBytes($agentSessionPath, $previousSessionBytes) }
        else { Remove-Item -LiteralPath $agentSessionPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $agentCommandPath) {
            try { if ((Get-Content -LiteralPath $agentCommandPath -Raw -Encoding UTF8 | ConvertFrom-Json).id -like "$progressionCommandPrefix*") { Remove-Item -LiteralPath $agentCommandPath -Force } } catch { }
        }
        if (Test-Path -LiteralPath $agentResponseRoot) {
            Get-ChildItem -LiteralPath $agentResponseRoot -File -Filter "$progressionCommandPrefix*.json" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        $keepVerifiedFixture = $RetainDisposableSave -and $recruitmentProgressionPassed -and (Test-Path -LiteralPath $progressionSavePath)
        if ($disposableSaveOwned -and -not $keepVerifiedFixture -and (Test-Path -LiteralPath $progressionSavePath)) {
            $saveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $fullDisposableSavePath = [IO.Path]::GetFullPath($progressionSavePath)
            if (-not $fullDisposableSavePath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Disposable save cleanup path escaped Game Saves.' }
            Get-ChildItem -LiteralPath $saveDirectory -File -Filter "$progressionSaveName*" | Remove-Item -Force
        }
        $keepPersistentStoryModeSave = $StoryModeEycPersistentSeed -and $persistentStoryModeSaveOwned -and $persistentStoryModeSaveCompleted -and $storyModeEycReadyObserved -and -not $crashDetected
        if ($persistentStoryModeSaveOwned -and -not $keepPersistentStoryModeSave -and (Test-Path -LiteralPath $persistentStoryModeSavePath)) {
            $saveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $fullPersistentSavePath = [IO.Path]::GetFullPath($persistentStoryModeSavePath)
            if (-not $fullPersistentSavePath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Persistent StoryMode save cleanup path escaped Game Saves.' }
            Remove-Item -LiteralPath $fullPersistentSavePath -Force
        }
    }
}

$saveDigestAfter = Get-SaveManifestDigest
$remainingBannerlordProcesses = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
$gameProcessesClean = $remainingBannerlordProcesses.Count -eq 0
if ($storyModeNativeInquiryTestSessionCreated) {
    if (Test-Path -LiteralPath $agentSessionPath) {
        try {
            $testSessionNow = Get-Content -LiteralPath $agentSessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([int]$testSessionNow.processId -eq [int]$bannerlordPid) { Remove-Item -LiteralPath $agentSessionPath -Force }
            else { throw 'Native Inquiry test session ownership changed before cleanup.' }
        }
        catch { $harnessFailureObserved = $true; $storyModeNativeInquiryResponseFailure = 'Test-only Agent CLI session cleanup failed.' }
    }
    $testCommandIds = @($storyModeNativeInquiryResponseCommandId, $storyModeNativeInquiryStateCommandId) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    if (Test-Path -LiteralPath $agentCommandPath) {
        try {
            $pendingTestCommand = Get-Content -LiteralPath $agentCommandPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($testCommandIds -contains [string]$pendingTestCommand.id) { Remove-Item -LiteralPath $agentCommandPath -Force }
        } catch { }
    }
    foreach ($processingFile in Get-ChildItem -LiteralPath $agentProtocolRoot -File -Filter 'command-*.processing' -ErrorAction SilentlyContinue) {
        try {
            $processingCommand = Get-Content -LiteralPath $processingFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($testCommandIds -contains [string]$processingCommand.id) { Remove-Item -LiteralPath $processingFile.FullName -Force }
        } catch { }
    }
    if (Test-Path -LiteralPath $agentResponseRoot) {
        foreach ($testCommandId in $testCommandIds) {
            Get-ChildItem -LiteralPath $agentResponseRoot -File -Filter "$testCommandId.*.json" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $gameProcessesClean) {
        $harnessFailureObserved = $true
        $storyModeNativeInquiryResponseFailure = 'Bannerlord process cleanup was not verified after the Native Inquiry test.'
    }
}
$saveDigestForComparison = if ($RetainDisposableSave -and $progressionSaveName) { Get-SaveManifestDigest -ExcludeSaveName $progressionSaveName }
elseif ($StoryModeEycPersistentSeed -and $PersistentStoryModeSaveName) { Get-SaveManifestDigest -ExcludeSaveName $PersistentStoryModeSaveName }
else { $saveDigestAfter }
$saveStateUnchanged = $saveDigestBefore -eq $saveDigestForComparison
$retainedDisposableSave = [bool]($RetainDisposableSave -and $disposableSaveOwned -and $progressionSaveName -and (Test-Path -LiteralPath $progressionSavePath))
$retainedPersistentStoryModeSave = [bool]($StoryModeEycPersistentSeed -and $persistentStoryModeSaveOwned -and $persistentStoryModeSaveCompleted -and (Test-Path -LiteralPath $persistentStoryModeSavePath))
if ($StoryModeEycLiveModelEvaluation -and $storyModeAgentHostReceiptPath -and (Test-Path -LiteralPath $storyModeAgentHostReceiptPath -PathType Leaf)) {
    try {
        $storyModeHostReceipt = Get-Content -LiteralPath $storyModeAgentHostReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $storyModeAgentHostReceiptCaptured = $true
        $storyModeAgentUsageSource = 'host-lifecycle-receipt'
        $storyModeAgentNativeActionsExecuted = [Math]::Max(0, [int]$storyModeHostReceipt.actionsExecuted)
        $storyModeAgentDecisionCount = [Math]::Max(0, [int]$storyModeHostReceipt.decisionCount)
        $storyModeAgentPromptTokens = [Math]::Max(0, [long]$storyModeHostReceipt.promptTokens)
        $storyModeAgentCompletionTokens = [Math]::Max(0, [long]$storyModeHostReceipt.completionTokens)
        $storyModeAgentPromptCacheHitTokens = $storyModeHostReceipt.providerPromptCacheHitTokens
        $storyModeAgentPromptCacheMissTokens = $storyModeHostReceipt.providerPromptCacheMissTokens
        $storyModeAgentActualCostEstimateCny = $storyModeHostReceipt.providerActualCostEstimateCny
        $storyModeAgentReservedCostUpperBoundCny = $storyModeHostReceipt.providerReservedCostUpperCny
        $storyModeAgentFailureCode = if (-not [string]::IsNullOrWhiteSpace([string]$storyModeHostReceipt.failureCode)) { [string]$storyModeHostReceipt.failureCode } else { [string]$storyModeHostReceipt.error }
        $storyModeAgentFailureExceptionType = [string]$storyModeHostReceipt.failureExceptionType
        $storyModeAgentFailureLocation = [string]$storyModeHostReceipt.failureLocation
        $storyModeOriginalEstablishYourClanCompleted = $storyModeHostReceipt.status -eq 'completed' -and
            $storyModeHostReceipt.termination.goalVerified -eq $true
    }
    catch { $harnessFailureObserved = $true }
}
if ($StoryModeEycLiveModelEvaluation -and -not $storyModeAgentHostReceiptCaptured) {
    $traceUsage = Measure-StoryModeAgentUsageFromTrace $storyModeAgentProgressEntries.ToArray()
    if ($traceUsage.DecisionCount -gt 0) {
        $storyModeAgentUsageSource = 'harness-provider-decision-trace'
        $storyModeAgentDecisionCount = $traceUsage.DecisionCount
        $storyModeAgentPromptTokens = $traceUsage.PromptTokens
        $storyModeAgentCompletionTokens = $traceUsage.CompletionTokens
        $storyModeAgentPromptCacheHitTokens = $traceUsage.PromptCacheHitTokens
        $storyModeAgentPromptCacheMissTokens = $traceUsage.PromptCacheMissTokens
        $storyModeAgentActualCostEstimateCny = $traceUsage.EstimatedCostCny
        $storyModeAgentProviderDecisionCostsComplete = $traceUsage.AllDecisionCostRowsPresent
        $storyModeAgentReservedCostUpperBoundCny = $traceUsage.ReservedCostUpperBoundCny
        $storyModeAgentNativeActionsExecuted = $null
    }
}
$storyModeAgentNativeActionTraceObserved = @($storyModeAgentProgressEntries | Where-Object {
    $_.event -eq 'objective-subflow-result' -and $null -ne $_.actionsExecuted -and [int]$_.actionsExecuted -gt 0
}).Count -gt 0
$issueProbeExpected = -not $StoryModeEycSetup -and -not $ValidateRecruitmentProgression -and [bool]($visibleIssueTypes -match ':[^,]+')
$issueConversationProbeApplicable = $issueProbeExpected
$issueConversationProbePassed = if ($issueProbeExpected) {
    $issueConversationProbeStatus -eq 'opened' -and $issueConversationOfferOption -and ($issueConversationBriefReached -or $issueConversationOfferDenied) -and $issueConversationClockBefore -eq $issueConversationClockAfter
} else {
    $null
}
$issueConversationProbeSkipped = -not $issueProbeExpected -and $issueConversationProbeStatus -like 'skipped*'
$issueConversationProbeOutcomeValid = ($issueConversationProbeApplicable -and $issueConversationProbePassed) -or $issueConversationProbeSkipped
$acceptanceChecks = [ordered]@{
    gameStarted = $gameStarted
    nativeNewCampaignRequested = $startRequested
    introSkipped = $introSkippedObserved
    backgroundSelected = $backgroundChoiceObserved
    characterCreationCompleted = $creationCompleted
    initialObservationCaptured = $initialSnapshotCaptured
    mapState = ($mapState -eq 'MapState')
    noCrash = (-not $crashDetected)
    noHarnessFailure = (-not $harnessFailureObserved)
    noUnplannedCampaignSave = (-not $campaignSaveRequested -or ($StoryModeEycPersistentSeed -and $persistentStoryModeSaveCompleted))
    unrelatedSaveManifestUnchanged = $saveStateUnchanged
    bannerlordAutoSaveDisabledDuringRun = ($null -ne $autoSaveSettingGuard -and $autoSaveIntervalDuring -eq -1)
    bannerlordAutoSaveSettingRestored = ($null -ne $autoSaveSettingRestoration -and [bool]$autoSaveSettingRestoration.Restored -and $autoSaveIntervalAfter -eq $autoSaveIntervalBefore)
    bannerlordSoundMutedDuringRun = ($null -ne $gameSoundSettingGuard -and $gameSoundDisabledDuring -eq 1)
    bannerlordSoundSettingRestored = ($null -ne $gameSoundSettingRestoration -and [bool]$gameSoundSettingRestoration.Restored -and $gameSoundDisabledAfter -eq $gameSoundDisabledBefore)
    noNativeAutoSaveObserved = (-not $nativeAutoSaveDetected)
    requestedDisposableSaveRetained = (-not $RetainDisposableSave -or $retainedDisposableSave)
    requestedPersistentStoryModeSaveRetained = (-not $StoryModeEycPersistentSeed -or $retainedPersistentStoryModeSave)
    windowLayout = ($windowLayoutApplied -and $windowLayout.Width -eq 840 -and $windowLayout.Height -eq 472)
    gameProcessesClean = $gameProcessesClean
}
if ($StoryModeEycSetup) {
    $acceptanceChecks.storyModeOfficialTutorialSkipSelected = $storyModeTutorialSkipSelected
    $acceptanceChecks.storyModeOfficialTutorialSkipConfirmed = $storyModeTutorialSkipConfirmed
    $acceptanceChecks.originalEstablishYourClanQuestNaturallyActive = $storyModeEycReadyObserved
    $requiredNativeFrames = @('brother-conversation-start', 'tutorial-skip-option-visible', 'tutorial-skip-confirmation-visible', 'campaign-map-after-tutorial-skip-settled')
    if (-not $StoryModeEycLiveModelEvaluation -or $storyModeEycReadyObserved) { $requiredNativeFrames += 'eyc-map-render-settled' }
    if ($StoryModeNativeMenuLeaveEvaluation) { $requiredNativeFrames += 'training-field-menu-exited' }
    $allRequiredNativeFramesPresent = @($requiredNativeFrames | Where-Object { -not $storyModeNativeFrameNames.Contains($_) }).Count -eq 0
    $requiredFrameHashes = @($requiredNativeFrames | ForEach-Object { [string]$storyModeNativeFrameHashes[$_] } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $distinctRequiredFrameHashes = @($requiredFrameHashes | Sort-Object -Unique)
    $storyModeNativeFramesPassed = $allRequiredNativeFramesPresent -and $requiredFrameHashes.Count -eq $requiredNativeFrames.Count -and $distinctRequiredFrameHashes.Count -eq $requiredNativeFrames.Count
    if ($allRequiredNativeFramesPresent -and -not $storyModeNativeFramesPassed) { $harnessFailureObserved = $true; $acceptanceChecks.noHarnessFailure = $false }
    $acceptanceChecks.storyModeNativeFrames = $storyModeNativeFramesPassed
    if ($StoryModeNativeMenuLeaveEvaluation) {
        $acceptanceChecks.storyModeNativeMenuLeaveRequested = $storyModeNativeLeaveRequested
        $acceptanceChecks.storyModeNativeMenuLeaveVerified = $storyModeNativeLeaveVerified
        $acceptanceChecks.storyModeNativeMenuLeaveUsedCurrentNativeEntry = $storyModeNativeLeaveBeforeMenu -eq 'training_field_menu' -and $storyModeNativeLeaveAfterMenu -ne 'training_field_menu' -and $storyModeNativeLeaveAfterSettlement -ne 'tutorial_training_field'
        $acceptanceChecks.storyModeNativeMenuLeaveKeptCampaignClockStopped = $storyModeNativeLeaveClockAfter -eq 'Stop'
        $acceptanceChecks.storyModeNativeMenuLeaveCampaignDayUnchanged = $null -ne $storyModeNativeLeaveCampaignDayBefore -and [Math]::Abs($storyModeNativeLeaveCampaignDayAfter - $storyModeNativeLeaveCampaignDayBefore) -le 0.001
        $acceptanceChecks.storyModeNativeMenuLeaveKeptEycActive = $storyModeEycReadyObserved
        $acceptanceChecks.storyModeNativeMenuLeavePostActionSnapshotCaptured = $null -ne $storyModeNativeLeavePostActionSnapshot
    }
    if ($StoryModeNativeInquiryResponseEvaluation) {
        $acceptanceChecks.storyModeNativeInquiryWasSupportedSingleButtonYesNo = $storyModeNativeLeavePostActionSnapshot.context.inquiryOpen -and
            $storyModeNativeLeavePostActionSnapshot.context.inquiry.supported -and
            $storyModeNativeLeavePostActionSnapshot.context.inquiry.kind -eq 'YesNoInquiry' -and
            $storyModeNativeLeavePostActionSnapshot.context.inquiry.affirmative.visible -and
            $storyModeNativeLeavePostActionSnapshot.context.inquiry.affirmative.enabled -and
            -not $storyModeNativeLeavePostActionSnapshot.context.inquiry.negative.visible
        $acceptanceChecks.storyModeNativeInquiryResponseRequested = $storyModeNativeInquiryResponseRequested
        $acceptanceChecks.storyModeNativeInquiryResponseVerified = $storyModeNativeInquiryResponseVerified
        $acceptanceChecks.storyModeNativeInquiryClosedAfterResponse = $null -ne $storyModeNativeInquiryStateAfterResponse -and
            -not $storyModeNativeInquiryStateAfterResponse.context.inquiryOpen -and -not $storyModeNativeInquiryStateAfterResponse.context.inquiry
        $acceptanceChecks.storyModeNativeInquiryKeptEycActive = $storyModeNativeInquiryStateAfterResponse -and
            @($storyModeNativeInquiryStateAfterResponse.quests | Where-Object { $_.id -eq 'rebuild_player_clan_storymode_quest' }).Count -eq 1
        $acceptanceChecks.storyModeNativeInquiryKeptCampaignDayAndStop = $null -ne $storyModeNativeInquiryBeforeDay -and
            $null -ne $storyModeNativeInquiryAfterDay -and
            [Math]::Abs($storyModeNativeInquiryAfterDay - $storyModeNativeInquiryBeforeDay) -le 0.001 -and
            $storyModeNativeInquiryStateAfterResponse.context.timeControlMode -eq 'Stop'
        if (-not $acceptanceChecks.storyModeNativeInquiryResponseVerified -or
            -not $acceptanceChecks.storyModeNativeInquiryClosedAfterResponse -or
            -not $acceptanceChecks.storyModeNativeInquiryKeptEycActive -or
            -not $acceptanceChecks.storyModeNativeInquiryKeptCampaignDayAndStop) {
            $harnessFailureObserved = $true
            $acceptanceChecks.noHarnessFailure = $false
        }
    }
    if ($StoryModeEycLiveModelEvaluation) {
        $acceptanceChecks.storyModeLiveHostStarted = $storyModeAgentHostStarted
        $acceptanceChecks.storyModeLiveHostReady = $storyModeAgentHostReady
        $acceptanceChecks.storyModeLiveHostTerminated = $storyModeAgentHostTerminalState -in @('Stopped','Completed','Failed')
        $acceptanceChecks.storyModeFocusLossEscapeMenuGuardInstalled = $storyModeFocusLossEscapeMenuGuardInstalled
        $acceptanceChecks.storyModeLiveModelProducedDecision = $storyModeAgentProgressEntries.Count -gt 0
        $acceptanceChecks.storyModeLiveNativeActionExecuted = ($storyModeAgentNativeActionsExecuted -gt 0) -or $storyModeAgentNativeActionTraceObserved
        $acceptanceChecks.storyModeLiveProviderPreflightReady = [bool]($providerProfile -and $providerProfile.CatalogListed -and -not [string]::IsNullOrWhiteSpace([string]$providerProfile.ModelId))
        if ($freeLlmApiProfile) {
            $storyModeFreeLLMAPIUpstreamTrace = Get-FreeLLMAPIProxyTrace -ProgressEntries @($storyModeAgentProgressEntries)
        }
    }
}
else {
    $acceptanceChecks.visibleIssuePoolObserved = $visibleIssuePoolObserved
    $acceptanceChecks.issueProbeOutcomeValid = $issueConversationProbeOutcomeValid
    $acceptanceChecks.progressionPassed = $recruitmentProgressionPassed
    $acceptanceChecks.expectedRenown = ($renown -eq 20)
}
$storyModeNativeLeaveInquiryForSummary = if ($StoryModeNativeMenuLeaveEvaluation -and $storyModeNativeLeavePostActionSnapshot -and $storyModeNativeLeavePostActionSnapshot.context.inquiry) {
    $storyModeNativeLeavePostActionSnapshot.context.inquiry | Select-Object supported,kind,title,text,affirmative,negative,timerShown,pauseGameActiveState
} else { $null }
$result = [ordered]@{
    Scenario = if ($StoryModeNativeInquiryResponseEvaluation) { 'FreshStoryModeOriginalTutorialSkipNativeInquiryCallback' } elseif ($StoryModeNativeMenuLeaveEvaluation) { 'FreshStoryModeOriginalTutorialSkipAndNativeTrainingFieldLeave' } elseif ($StoryModeEycSetup) { 'FreshStoryModeOriginalTutorialSkipToEstablishYourClan' } else { 'FreshCampaignCharacterCreationRenown' }
    GameMode = if ($StoryModeEycSetup) { 'StoryMode' } else { 'Sandbox' }
    Launcher = $launcher
    GameExecutable = $gameExe
    SteamClientReadiness = $steamReadiness
    GameProcessId = $bannerlordPid
    GameStarted = $gameStarted
    NativeNewCampaignRequested = $startRequested
    OptionalIntroSkipped = $introSkippedObserved
    StartupDialogReceipts = @($startupDialogReceipts)
    StartupDialogFailure = $startupDialogFailure
    AutoSelectedHighRenownBackground = $backgroundChoiceObserved
    VisibleIssueTypesBySettlement = $visibleIssueTypes
    IssueConversationProbeStatus = $issueConversationProbeStatus
    IssueConversationProbeApplicable = $issueConversationProbeApplicable
    IssueOfferOptionAvailable = $issueConversationOfferOption
    IssueBriefReached = $issueConversationBriefReached
    IssueOfferDeniedByNativeDialogue = $issueConversationOfferDenied
    QuestAcceptanceAvailable = $issueQuestAcceptanceAvailable
    IssueConversationProbePassed = $issueConversationProbePassed
    IssueConversationProbeSkipped = $issueConversationProbeSkipped
    IssueConversationClockBefore = $issueConversationClockBefore
    IssueConversationClockAfter = $issueConversationClockAfter
    IssueConversationOptionIds = $issueConversationOptions
    RecruitmentProgression = $recruitmentProgression
    DisposableSaveName = $progressionSaveName
    DisposableSavePath = if ($progressionSavePath -and (Test-Path -LiteralPath $progressionSavePath)) { $progressionSavePath } else { $null }
    DisposableSaveRetained = $retainedDisposableSave
    PersistentStoryModeSeed = [bool]$StoryModeEycPersistentSeed
    PersistentStoryModeSaveName = if ($StoryModeEycPersistentSeed) { $PersistentStoryModeSaveName } else { $null }
    PersistentStoryModeSavePath = if ($retainedPersistentStoryModeSave) { $persistentStoryModeSavePath } else { $null }
    PersistentStoryModeSaveHash = if ($retainedPersistentStoryModeSave) { $persistentStoryModeSaveHash } else { $null }
    PersistentStoryModeSaveRetained = $retainedPersistentStoryModeSave
    RecruitmentProgressionError = $recruitmentProgressionError
    CharacterCreationCompleted = $creationCompleted
    StoryModeOfficialTutorialSkipSelected = if ($StoryModeEycSetup) { $storyModeTutorialSkipSelected } else { $null }
    StoryModeOfficialTutorialSkipConfirmed = if ($StoryModeEycSetup) { $storyModeTutorialSkipConfirmed } else { $null }
    OriginalEstablishYourClanQuestNaturallyActive = if ($StoryModeEycSetup) { $storyModeEycReadyObserved } else { $null }
    StoryModeFirstMapStateObserved = if ($StoryModeEycSetup) { $storyModeMapReadyObserved } else { $null }
    StoryModeFirstMapMenuId = if ($StoryModeEycSetup) { $storyModeMapMenuId } else { $null }
    StoryModeFirstMapSettlementId = if ($StoryModeEycSetup) { $storyModeMapSettlementId } else { $null }
    StoryModeFirstMapSnapshotPath = if ($StoryModeEycSetup -and (Test-Path -LiteralPath $storyModeFirstMapSnapshotPath -PathType Leaf)) { $storyModeFirstMapSnapshotPath } else { $null }
    StoryModeFirstMapStateSettled = if ($StoryModeEycSetup) { $storyModeMapSettledObserved } else { $null }
    StoryModeTrainingFieldExitPath = if ($StoryModeEycSetup) { $storyModeTrainingFieldExitPath } else { $null }
    StoryModeNativeFrames = if ($StoryModeEycSetup) { @($storyModeNativeFrameNames) } else { $null }
    StoryModeNativeFrameSha256 = if ($StoryModeEycSetup) { $storyModeNativeFrameHashes } else { $null }
    StoryModeNativeFrameDistinctCount = if ($StoryModeEycSetup) { $distinctRequiredFrameHashes.Count } else { $null }
    StoryModeNativeFramesPassed = if ($StoryModeEycSetup) { $storyModeNativeFramesPassed } else { $null }
    StoryModeNativeMenuLeaveEvaluation = [bool]$StoryModeNativeMenuLeaveEvaluation
    StoryModeNativeMenuLeaveRequested = if ($StoryModeNativeMenuLeaveEvaluation) { $storyModeNativeLeaveRequested } else { $null }
    StoryModeNativeMenuLeaveVerified = if ($StoryModeNativeMenuLeaveEvaluation) { $storyModeNativeLeaveVerified } else { $null }
    StoryModeNativeMenuLeaveFailure = if ($StoryModeNativeMenuLeaveEvaluation) { $storyModeNativeLeaveFailure } else { $null }
    StoryModeNativeMenuLeaveBeforeMenu = if ($StoryModeNativeMenuLeaveEvaluation) { $storyModeNativeLeaveBeforeMenu } else { $null }
    StoryModeNativeMenuLeaveAfterMenu = if ($StoryModeNativeMenuLeaveEvaluation) { $storyModeNativeLeaveAfterMenu } else { $null }
    StoryModeNativeMenuLeaveAfterSettlement = if ($StoryModeNativeMenuLeaveEvaluation) { $storyModeNativeLeaveAfterSettlement } else { $null }
    StoryModeNativeMenuLeaveCampaignDayBefore = if ($StoryModeNativeMenuLeaveEvaluation) { $storyModeNativeLeaveCampaignDayBefore } else { $null }
    StoryModeNativeMenuLeaveCampaignDayAfter = if ($StoryModeNativeMenuLeaveEvaluation) { $storyModeNativeLeaveCampaignDayAfter } else { $null }
    StoryModeNativeMenuLeaveClockAfter = if ($StoryModeNativeMenuLeaveEvaluation) { $storyModeNativeLeaveClockAfter } else { $null }
    StoryModeNativeMenuLeavePostActionSnapshotPath = if ($StoryModeNativeMenuLeaveEvaluation -and $storyModeNativeLeavePostActionSnapshot) { $storyModeNativeLeaveSnapshotPath } else { $null }
    StoryModeNativeMenuLeaveInquiryOpenAfter = if ($StoryModeNativeMenuLeaveEvaluation -and $storyModeNativeLeavePostActionSnapshot) { [bool]$storyModeNativeLeavePostActionSnapshot.context.inquiryOpen } else { $null }
    StoryModeNativeMenuLeaveInquiry = $storyModeNativeLeaveInquiryForSummary
    StoryModeNativeInquiryResponseEvaluation = [bool]$StoryModeNativeInquiryResponseEvaluation
    StoryModeNativeInquiryResponseChoice = if ($StoryModeNativeInquiryResponseEvaluation) { 'affirmative' } else { $null }
    StoryModeNativeInquiryResponseRequested = if ($StoryModeNativeInquiryResponseEvaluation) { $storyModeNativeInquiryResponseRequested } else { $null }
    StoryModeNativeInquiryResponseVerified = if ($StoryModeNativeInquiryResponseEvaluation) { $storyModeNativeInquiryResponseVerified } else { $null }
    StoryModeNativeInquiryResponseFailure = if ($StoryModeNativeInquiryResponseEvaluation) { $storyModeNativeInquiryResponseFailure } else { $null }
    StoryModeNativeInquiryResponseReceipt = if ($StoryModeNativeInquiryResponseEvaluation) { $storyModeNativeInquiryResponseReceipt } else { $null }
    StoryModeNativeInquiryStateAfterResponse = if ($StoryModeNativeInquiryResponseEvaluation -and $storyModeNativeInquiryStateAfterResponse) {
        [ordered]@{
            gameState = $storyModeNativeInquiryStateAfterResponse.context.gameState
            menuId = $storyModeNativeInquiryStateAfterResponse.context.menuId
            inquiryOpen = $storyModeNativeInquiryStateAfterResponse.context.inquiryOpen
            storyModeEstablishClanStatus = $storyModeNativeInquiryStateAfterResponse.storyModeEstablishClanStatus.status
            campaignDay = $storyModeNativeInquiryAfterDay
            timeControlMode = $storyModeNativeInquiryStateAfterResponse.context.timeControlMode
            questIds = @($storyModeNativeInquiryStateAfterResponse.quests | ForEach-Object { $_.id })
        }
    } else { $null }
    StoryModeLiveModelEvaluation = [bool]$StoryModeEycLiveModelEvaluation
    StoryModeAgentHostStarted = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentHostStarted } else { $null }
    StoryModeAgentHostStartRequested = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentHostStartRequested } else { $null }
    StoryModeAgentHostReady = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentHostReady } else { $null }
    StoryModeFocusLossEscapeMenuGuardInstalled = if ($StoryModeEycLiveModelEvaluation) { $storyModeFocusLossEscapeMenuGuardInstalled } else { $null }
    StoryModeAgentHostTerminalState = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentHostTerminalState } else { $null }
    StoryModeAgentHostTerminalDetail = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentHostTerminalDetail } else { $null }
    StoryModeAgentHostReceiptCaptured = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentHostReceiptCaptured } else { $null }
    StoryModeAgentUsageSource = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentUsageSource } else { $null }
    StoryModeAgentProviderDecisionCostsComplete = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentProviderDecisionCostsComplete } else { $null }
    StoryModeAgentNativeActionTraceObserved = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentNativeActionTraceObserved } else { $null }
    StoryModeStartupFailure = if ($StoryModeEycLiveModelEvaluation) { $storyModeStartupFailure } else { $null }
    StoryModeAgentDecisionCount = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentDecisionCount } else { $null }
    StoryModeAgentNativeActionsExecuted = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentNativeActionsExecuted } else { $null }
    StoryModeAgentPromptTokens = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentPromptTokens } else { $null }
    StoryModeAgentCompletionTokens = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentCompletionTokens } else { $null }
    StoryModeAgentPromptCacheHitTokens = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentPromptCacheHitTokens } else { $null }
    StoryModeAgentPromptCacheMissTokens = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentPromptCacheMissTokens } else { $null }
    StoryModeAgentActualCostEstimateCny = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentActualCostEstimateCny } else { $null }
    StoryModeAgentReservedCostUpperBoundCny = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentReservedCostUpperBoundCny } else { $null }
    StoryModeAgentFailureCode = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentFailureCode } else { $null }
    StoryModeAgentFailureExceptionType = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentFailureExceptionType } else { $null }
    StoryModeAgentFailureLocation = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentFailureLocation } else { $null }
    StoryModeOriginalEstablishYourClanCompleted = if ($StoryModeEycLiveModelEvaluation) { $storyModeOriginalEstablishYourClanCompleted } else { $null }
    FreeLLMAPIProfile = if ($StoryModeEycLiveModelEvaluation) { $freeLlmApiProfile } else { $null }
    FreeLLMAPIUpstreamTrace = if ($StoryModeEycLiveModelEvaluation) { $storyModeFreeLLMAPIUpstreamTrace } else { $null }
    StoryModeModelProviderProfile = if ($StoryModeEycLiveModelEvaluation) { $providerProfile } else { $null }
    StoryModeAgentProgressPath = if ($StoryModeEycLiveModelEvaluation) { $storyModeAgentProgressPath } else { $null }
    StoryModeAgentDecisions = if ($StoryModeEycLiveModelEvaluation) { @($storyModeAgentProgressEntries) } else { $null }
    BannerlordProcessesCleanAtExit = $gameProcessesClean
    StoryModeVisualCapture = if ($StoryModeEycSetup) { $storyModeVideoCaptureResult } else { $null }
    StoryModeVisualCaptureError = if ($StoryModeEycSetup) { $storyModeVideoCaptureError } else { $null }
    StoryModeVideoRetained = if ($StoryModeEycSetup) { $storyModeVideoCaptureRetained } else { $null }
    StartupDialogSnapshots = @($startupDialogSnapshots)
    InitialAgentObservationCaptured = $initialSnapshotCaptured
    InitialAgentObservationPath = if ($initialSnapshotCaptured) { $snapshotArtifactPath } else { $null }
    ChronicleCampaignInstanceId = $campaignInstanceId
    ClanRenown = $renown
    ExpectedClanRenown = if ($StoryModeEycSetup) { $null } else { 20 }
    MapState = $mapState
    CampaignClockMode = $clock
    CharacterCreationStagesObserved = @($stageIndices | Sort-Object)
    CrashDetected = $crashDetected
    WindowLayoutApplied = $windowLayoutApplied
    WindowX = if ($windowLayout) { $windowLayout.X } else { $null }
    WindowY = if ($windowLayout) { $windowLayout.Y } else { $null }
    WindowWidth = if ($windowLayout) { $windowLayout.Width } else { $null }
    WindowHeight = if ($windowLayout) { $windowLayout.Height } else { $null }
    NoSaveRequested = (-not $campaignSaveRequested -and -not $StoryModeEycPersistentSeed)
    SaveDirectoryMetadataUnchanged = $saveStateUnchanged
    BannerlordAutoSaveIntervalBefore = $autoSaveIntervalBefore
    BannerlordAutoSaveIntervalDuring = $autoSaveIntervalDuring
    BannerlordAutoSaveIntervalAfter = $autoSaveIntervalAfter
    BannerlordAutoSaveDisabledForHarness = [bool]($autoSaveSettingGuard -and $autoSaveIntervalDuring -eq -1)
    BannerlordAutoSaveRestorationStatus = if ($autoSaveSettingRestoration) { $autoSaveSettingRestoration.Status } else { $null }
    BannerlordAutoSaveRestorationError = $autoSaveSettingRestorationError
    BannerlordSoundDisabledBefore = $gameSoundDisabledBefore
    BannerlordSoundDisabledDuring = $gameSoundDisabledDuring
    BannerlordSoundDisabledAfter = $gameSoundDisabledAfter
    BannerlordSoundMutedForHarness = [bool]($gameSoundSettingGuard -and $gameSoundDisabledDuring -eq 1)
    BannerlordSoundRestorationStatus = if ($gameSoundSettingRestoration) { $gameSoundSettingRestoration.Status } else { $null }
    BannerlordSoundRestorationError = $gameSoundSettingRestorationError
    NativeAutoSaveObserved = $nativeAutoSaveDetected
    AcceptanceChecks = $acceptanceChecks
    RglLog = $rglLog
    WatchdogLog = $watchdogLog
    CrashWindowTitle = $crashWindowTitle
    CrashWindowCapture = $crashWindowCaptureResult
    CrashWindowCaptureError = $crashWindowCaptureError
    CrashWindowCaptureVideoRetained = $crashWindowCaptureRetained
    CrashExceptionPath = if ($bannerlordPid -and $env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashException-$bannerlordPid.txt" } else { $null }
    CrashExceptionCaptured = [bool]($bannerlordPid -and $env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP "CrashException-$bannerlordPid.txt")))
    CrashFaultAddress = $crashFaultAddress
    CrashFaultModule = $crashFaultModule
    CrashModuleInventory = $crashModuleInventory
    CrashModuleCaptureError = $crashModuleCaptureError
    Passed = (@($acceptanceChecks.Values | Where-Object { -not [bool]$_ }).Count -eq 0)
}
$resultJson = $result | ConvertTo-Json -Depth 8
if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) {
    Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'FreshCampaignResult.json') -Value $resultJson -Encoding UTF8
}
$resultJson
if (-not $result.Passed) { exit 1 }
