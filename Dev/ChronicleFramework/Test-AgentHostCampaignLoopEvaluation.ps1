[CmdletBinding()]
param(
    [ValidateRange(1,3)][int]$Runs = 1,
    [ValidateRange(5,30)][int]$FrameRate = 10,
    [string]$CleanupPreparedSaveName,
    [switch]$VillageToolsQuest,
    [switch]$BattleSimulationLoop,
    [string]$BattleSourceSaveName = 'AgentBridgeLifecycle'
)

$ErrorActionPreference = 'Stop'
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

if (-not [string]::IsNullOrWhiteSpace($CleanupPreparedSaveName)) {
    if (-not ($CleanupPreparedSaveName.StartsWith('ChronicleW7K-', [StringComparison]::Ordinal) -or $CleanupPreparedSaveName.StartsWith('ChronicleW7L-', [StringComparison]::Ordinal))) { throw 'Cleanup-only mode accepts only Harness-owned ChronicleW7K/W7L prepared save names.' }
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Refusing prepared-save cleanup while a Bannerlord process is running.' }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing prepared-save cleanup while a Chronicle Agent CLI session is active.' }
    $saveDirectory = Join-Path $documentsPath 'Mount and Blade II Bannerlord\Game Saves'
    $saveRoot = [IO.Path]::GetFullPath($saveDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $preparedSavePath = [IO.Path]::GetFullPath((Join-Path $saveRoot ($CleanupPreparedSaveName + '.sav')))
    $preparedBaseName = [IO.Path]::GetFileNameWithoutExtension($preparedSavePath)
    if (-not $preparedSavePath.StartsWith($saveRoot, [StringComparison]::OrdinalIgnoreCase) -or -not ($preparedBaseName.StartsWith('ChronicleW7K-', [StringComparison]::Ordinal) -or $preparedBaseName.StartsWith('ChronicleW7L-', [StringComparison]::Ordinal))) { throw 'Prepared save path escaped the Harness-owned ChronicleW7K/W7L Game Saves boundary.' }
    $removed = -not (Test-Path -LiteralPath $preparedSavePath -PathType Leaf)
    if (-not $removed) {
        [IO.File]::Delete($preparedSavePath)
        $removed = -not (Test-Path -LiteralPath $preparedSavePath -PathType Leaf)
    }
    if (-not $removed) { throw 'Harness-owned prepared save still exists after cleanup.' }
    [pscustomobject]@{ CleanupOnly = $true; PreparedSaveName = $CleanupPreparedSaveName; Removed = $true; BannerlordProcessCount = 0; AgentSessionPresent = $false } | ConvertTo-Json -Compress
    exit 0
}

if ($BattleSimulationLoop) {
    if ($BattleSourceSaveName -notmatch '^[A-Za-z0-9_-]{1,48}$' -or $BattleSourceSaveName.EndsWith('.sav', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Battle evaluation source must be one Game Saves basename without a path or extension; no Host or model was started.'
    }
}

if (Test-Path -LiteralPath $sessionPath -PathType Leaf) {
    $staleSession = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $staleSaveName = [string]$staleSession.saveName
    $stalePid = [int]$staleSession.processId
    if (-not ($staleSaveName.StartsWith('ChronicleW7K-', [StringComparison]::Ordinal) -or $staleSaveName.StartsWith('ChronicleW7L-', [StringComparison]::Ordinal))) {
        throw 'A stale CLI session exists, but its save name is not a Harness-owned ChronicleW7K/W7L fixture; preserving it.'
    }
    if (@(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -gt 0 -or (Get-Process -Id $stalePid -ErrorAction SilentlyContinue)) {
        throw 'A ChronicleW7K session still has a live Bannerlord/session process; refusing automatic recovery.'
    }

    $cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
    $stopOutput = ''
    try { $stopOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli stop -AsJson 2>&1 | Out-String }
    catch { $stopOutput = $_.Exception.Message }
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'The stale CLI session did not clear through the Agent CLI recovery path.' }
    $cleanupOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -CleanupPreparedSaveName $staleSaveName 2>&1 | Out-String
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
    $failure = $null
    try {
        . (Join-Path $PSScriptRoot 'Get-FreeLLMAPIProfile.ps1')
        $freeLlmApiProfile = Initialize-FreeLLMAPIProfile
        $providerBaseUrl = [string]$freeLlmApiProfile.BaseUrl
        $providerModelId = [string]$freeLlmApiProfile.RequestedModelId

        $mcmFixtureDirectory = Join-Path $runTemp 'MCM\Global\ChronicleFramework'
        New-Item -ItemType Directory -Path $mcmFixtureDirectory -Force | Out-Null
        $profilePath = Join-Path $mcmFixtureDirectory 'ChronicleAgentSettings.json'
        [ordered]@{ OllamaBaseUrl = $providerBaseUrl; ModelId = $providerModelId } | ConvertTo-Json -Compress | Set-Content -LiteralPath $profilePath -Encoding UTF8
        $env:CHRONICLE_AGENT_PROFILE_PATH = $profilePath
        if ($VillageToolsQuest) {
            $prepOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-AgentVillageToolsQuestFixturePreparation.ps1') -SourceSaveName 'AgentBridgeLifecycle' -MaxVillages 4 2>&1 | Out-String
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
            $childOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveTest -LoadSaveName $preparedSaveName -VillageToolsQuestLoop -AgentHostRuntime -FrameRate $FrameRate 2>&1 | Out-String
        }
        elseif ($BattleSimulationLoop) {
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
            $childOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveTest -LoadSaveName $battleFixtureSaveName -BattleSimulationLoop -AgentHostRuntime -FrameRate $FrameRate 2>&1 | Out-String
        }
        else {
            $childOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveTest -ArrivalLoop -AgentHostRuntime -FrameRate $FrameRate 2>&1 | Out-String
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
        if ($BattleSimulationLoop -and $battleFixtureSaveName) {
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
        $env:CHRONICLE_HARNESS_TEMP = $priorHarnessTemp
        $env:TEMP = $priorTemp
        $env:TMP = $priorTmp
        if ($null -eq $priorProviderProfilePath) { Remove-Item Env:CHRONICLE_AGENT_PROFILE_PATH -ErrorAction SilentlyContinue }
        else { $env:CHRONICLE_AGENT_PROFILE_PATH = $priorProviderProfilePath }
    }

    $trace = if ($liveResult) { $liveResult.Trace } else { $null }
    $modelSteps = if ($trace -and $trace.Trace) { @($trace.Trace) } else { @() }
    $nativeActions = @($modelSteps | Where-Object { $_.actionExecuted -and $_.actionReceipt.status -eq 'completed' })
    $observeAgainSteps = @($modelSteps | Where-Object { $_.control.kind -eq 'bounded-observe-again' -and -not $_.actionExecuted })
    $noGameProcesses = @(Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue).Count -eq 0
    $noSessionFile = -not (Test-Path -LiteralPath $sessionPath -PathType Leaf)
    if ($BattleSimulationLoop) {
        $battleOutcome = if ($trace) { $trace.BattleOutcome } else { $null }
        $battleTargetId = if ($battleOutcome) { [string]$battleOutcome.TargetPartyId } else { '' }
        $clockActions = if ($trace) { @($trace.NativeClockActions) } else { @() }
        $battleActionSequence = @($nativeActions | ForEach-Object { [string]$_.actionReceipt.action })
        $providerRoutes = if ($trace -and $trace.ProviderRouteHistory) { @($trace.ProviderRouteHistory) } else { @() }
        # Source cleanliness is checked at the live test boundary; this evaluator
        # also requires the real provider route and a freshly observed target.
        $battleEvidenceVerified = (
            $childExitCode -eq 0 -and $liveResult -and [bool]$liveResult.Passed -and
            [bool]$trace.BattleSimulationVerified -and [bool]$trace.BattleReturnToMapVerified -and
            $battleTargetId.Length -gt 0 -and [double]::IsFinite([double]$trace.BattleRenownBefore) -and
            [double]::IsFinite([double]$trace.BattleRenownAfter) -and $clockActions.Count -eq 0 -and
            $battleActionSequence.Contains('mapPartyTargets') -and $battleActionSequence.Contains('menuSelect') -and
            $battleActionSequence.Contains('battleFinish') -and
            [string]$battleOutcome.SendTroopsOption -ceq 'str_order_attack' -and [string]$battleOutcome.SimulationState -ne 'unknown' -and
            [string]$battleOutcome.PlayerOutcome -in @('captured','retreated','resolved-native-battle') -and
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
        if (-not $passed -and -not $failure) { $failure = 'One or more real-model Native BattleSimulation, current target, actual outcome, no-clock, visual, source, or cleanup assertions failed.' }
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
        battleOutcome = if ($BattleSimulationLoop) { $battleOutcome } else { $null }
        battleTargetPreflight = if ($BattleSimulationLoop -and $liveResult) { $liveResult.BattleTargetPreflight } else { $null }
        battleSourceSaveName = if ($BattleSimulationLoop) { $BattleSourceSaveName } else { $null }
        battleSourceHashBefore = if ($BattleSimulationLoop) { $battleSourceHashBefore } else { $null }
        battleSourceHashAfter = if ($BattleSimulationLoop) { $battleSourceHashAfter } else { $null }
        battleDisposableSaveRemoved = if ($BattleSimulationLoop) { $battleFixtureRemoved } else { $null }
        battleActionSequence = if ($BattleSimulationLoop) { $battleActionSequence } else { @() }
        battleSimulationVerified = if ($BattleSimulationLoop -and $trace) { [bool]$trace.BattleSimulationVerified } else { $null }
        renownBefore = if ($BattleSimulationLoop -and $trace) { $trace.BattleRenownBefore } else { $null }
        renownAfter = if ($BattleSimulationLoop -and $trace) { $trace.BattleRenownAfter } else { $null }
        observedIssueMarkerMatchedTalkTarget = if ($VillageToolsQuest) { [bool]$visibleIssueMarkerVerified } else { $null }
        nativeToolTradeCommits = if ($VillageToolsQuest) { @($tradeCommits | ForEach-Object { $_.actionReceipt.data }) } else { @() }
        preparedSaveRemoved = if ($BattleSimulationLoop) { $battleFixtureRemoved } else { $preparedSaveRemoved }
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
    ProviderKind = 'FreeLLMAPI-routed external model through the configured free endpoint'
    RunCount = $Runs
    DistinctCampaignSeeds = 1
    Threshold = if ($BattleSimulationLoop) {
        [ordered]@{
            successfulRuns = $Runs
            targetMustBeCurrentNativeVisibleHostileBandit = $true
            requiresNativeBanditFightDialogueWhenMeeting = 'bandit_start_defender_1'
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
            requiresFreeLlmApiRoutedModel = $true
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
