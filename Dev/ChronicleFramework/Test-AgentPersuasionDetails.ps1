[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [string]$TargetSettlementId = 'town_V1',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$frameRoot = if ($tempPath) { $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualPersuasionDetails' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'persuasion-details-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$resultName = 'PersuasionDetails-Result.json'
$frameConversation = Join-Path $frameRoot 'persuasion-conversation.bmp'
$framePersuasion = Join-Path $frameRoot 'persuasion-native-panel.bmp'
$frameAnswerList = Join-Path $frameRoot 'persuasion-answer-list-before-task.bmp'
$frameAfterArgument = Join-Path $frameRoot 'persuasion-after-argument.bmp'
$failedStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Disposable Campaign fixture not found: $LoadSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$sourceHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($exitCode -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-frame-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($receipt.status -ne 'completed' -or -not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -lt 4096)
        { throw "Native Persuasion frame was not captured: $Path" }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $failedStep = 'load-disposable-Campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState') { throw "Persuasion fixture must start on Campaign Map; got $($initial.state.context.gameState)." }

    $failedStep = 'travel-to-visible-Town'
    $mapTargets = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId', "$prefix-map-targets")
    $target = @($mapTargets.data.mapSettlementTargets | Where-Object { $_.id -eq $TargetSettlementId -and -not $_.hostile } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Town '$TargetSettlementId' is not currently a visible safe map target." }
    $move = Invoke-AgentCli 'move' @('-SettlementId', $TargetSettlementId, '-CommandId', "$prefix-move")
    if ($move.status -ne 'completed') { throw "Native movement to Town was not accepted: $($move.error)" }
    $arrival = Wait-ForAgentSettlementArrival -CliPath $cli -SettlementId $TargetSettlementId -CommandPrefix "$prefix-arrival" -TimeoutSeconds $TimeoutSeconds
    if ($arrival.state.context.gameState -ne 'MapState' -or $arrival.state.location.currentSettlementId -ne $TargetSettlementId)
        { throw 'Campaign did not arrive at the Town menu.' }

    $failedStep = 'observe-current-native-Settlement-characters'
    $overlayCharacters = @($arrival.state.settlementOverlayCharacters | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.heroId) } | Select-Object -First 1)
    if ($overlayCharacters.Count -ne 1) { throw 'Current Town has no observed local Hero available for a quick Native conversation.' }
    $targetHeroId = [string]$overlayCharacters[0].heroId
    $failedStep = 'start-native-map-conversation'
    $talk = Invoke-AgentCli 'talkToSettlementHero' @('-HeroId', $targetHeroId, '-CommandId', "$prefix-talk") 30
    $conversation = $talk.state.context.conversation
    if ($talk.status -ne 'completed' -or $talk.state.context.gameState -ne 'MapState' -or -not $conversation -or [string]$conversation.heroId -ne $targetHeroId)
        { throw "Native Town conversation did not start for the observed Hero: $($talk.state.context | ConvertTo-Json -Depth 6 -Compress)" }
    Capture-EngineFrame $frameConversation 'conversation'

    $failedStep = 'verify-no-Persuasion-context-is-not-exposed'
    $withoutTask = Invoke-AgentCli 'persuasionDetails' @('-CommandId', "$prefix-no-persuasion") 30
    if ($withoutTask.status -ne 'completed' -or [bool]$withoutTask.data.available)
        { throw "persuasionDetails exposed a task when Native ConversationManager has no active Persuasion: $($withoutTask.data | ConvertTo-Json -Depth 6 -Compress)" }

    $failedStep = 'wait-for-Native-answer-list'
    $answerListDeadline = [DateTime]::UtcNow.AddSeconds(10)
    $nativeAnswers = $null
    do {
        $nativeAnswers = Invoke-AgentCli 'harnessCurrentConversationAnswers' @('-CommandId', "$prefix-answer-list") 30
        if ($nativeAnswers.status -ne 'completed') { throw "Native Conversation answer-list query failed: $($nativeAnswers.error)" }
        if ([bool]$nativeAnswers.data.isLoadingOver -and [int]$nativeAnswers.data.answerCount -gt 0) { break }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $answerListDeadline)
    if (-not [bool]$nativeAnswers.data.isLoadingOver -or [int]$nativeAnswers.data.answerCount -le 0) {
        Capture-EngineFrame $frameAnswerList 'answer-list-timeout'
        throw "Native UI never rendered a player answer row after conversation startup: $($nativeAnswers.data | ConvertTo-Json -Depth 7 -Compress)"
    }
    $visibleNativeAnswers = @($nativeAnswers.data.visibleOptions | Where-Object { $_.enabled } | Select-Object -First 1)
    if ($visibleNativeAnswers.Count -ne 1) { throw "Native AnswerList contains no enabled row: $($nativeAnswers.data | ConvertTo-Json -Depth 7 -Compress)" }
    Capture-EngineFrame $frameAnswerList 'answer-list-before-persuasion'

    $failedStep = 'seed-temporary-Native-Persuasion-on-current-option'
    $fixture = Invoke-AgentCli 'harnessSeedPersuasionFixture' @('-OptionId', [string]$visibleNativeAnswers[0].optionId, '-CommandId', "$prefix-seed") 30
    if ($fixture.status -ne 'completed' -or -not [bool]$fixture.data.persuasionActive)
        { throw "Native Persuasion fixture did not activate: $($fixture | ConvertTo-Json -Depth 6 -Compress)" }
    Capture-EngineFrame $framePersuasion 'persuasion'

    $failedStep = 'read-current-Native-Persuasion-VM'
    $beforeRead = Invoke-AgentCli 'state' @('-CommandId', "$prefix-before-read")
    $persuasion = Invoke-AgentCli 'persuasionDetails' @('-CommandId', "$prefix-details") 30
    if ($persuasion.status -ne 'completed' -or -not [bool]$persuasion.data.available -or $persuasion.data.nativeViewModel -ne 'MapConversationVM.DialogController.Persuasion')
        { throw "persuasionDetails did not read the active Native Persuasion view model: $($persuasion.data | ConvertTo-Json -Depth 7 -Compress)" }
    $visiblePersuasionOptions = @($persuasion.data.options | Where-Object { $_.clickable })
    if ($visiblePersuasionOptions.Count -eq 0 -or [int]$fixture.data.nativeAnswerCount -le 0)
        { throw "The Native Persuasion argument did not remain in the rendered answer list: $($persuasion.data | ConvertTo-Json -Depth 7 -Compress); Harness fixture VM: $($fixture.data | ConvertTo-Json -Depth 6 -Compress)" }
    $matchingOption = @($visiblePersuasionOptions | Where-Object { $_.optionId -eq [string]$visibleNativeAnswers[0].optionId } | Select-Object -First 1)
    if ($matchingOption.Count -ne 1) { throw "Native answer list and PersuasionVM did not map the same option ID: $($persuasion.data | ConvertTo-Json -Depth 7 -Compress)" }
    if ([double]$persuasion.data.progress -lt 0 -or [double]$persuasion.data.progress -gt [double]$persuasion.data.goal -or
        $persuasion.data.progressIndicators.Count -ne [int][Math]::Round([double]$persuasion.data.goal))
        { throw "Native Persuasion progress/goal indicators do not match: $($persuasion.data | ConvertTo-Json -Depth 7 -Compress)" }
    foreach ($chanceName in @('successChance','failChance','criticalSuccessChance','criticalFailChance')) {
        $chance = [int]$matchingOption[0].$chanceName
        if ($chance -lt 0 -or $chance -gt 100) { throw "Native Persuasion $chanceName is outside the 0-100 range: $chance" }
    }
    $repeat = Invoke-AgentCli 'persuasionDetails' @('-CommandId', "$prefix-repeat") 30
    $afterRead = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-read")
    $readOnlyStable = ([double]$beforeRead.campaignDay -eq [double]$afterRead.campaignDay -and
        [string]$beforeRead.state.context.timeControlMode -eq [string]$afterRead.state.context.timeControlMode -and
        [int]$beforeRead.state.economy.gold -eq [int]$afterRead.state.economy.gold -and
        [double]$beforeRead.state.economy.influence -eq [double]$afterRead.state.economy.influence -and
        [string]$conversation.heroId -eq [string]$afterRead.state.context.conversation.heroId -and
        ($persuasion.data | ConvertTo-Json -Depth 10 -Compress) -eq ($repeat.data | ConvertTo-Json -Depth 10 -Compress))
    if (-not $readOnlyStable) { throw 'Persuasion query changed the conversation/world state or returned unstable native VM data.' }

    $failedStep = 'submit-current-visible-Native-Persuasion-option'
    $dialogueSelection = Invoke-AgentCli 'dialogueSelect' @('-OptionId', [string]$matchingOption[0].optionId, '-CommandId', "$prefix-visible-persuasion-choice") 30
    if ($dialogueSelection.status -ne 'completed') { throw "Visible Native Persuasion option was rejected: $($dialogueSelection.error)" }
    $afterSelection = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-visible-selection") 30
    $persuasionAfterSelection = Invoke-AgentCli 'persuasionDetails' @('-CommandId', "$prefix-after-visible-selection-details") 30
    Capture-EngineFrame $frameAfterArgument 'after-visible-argument'

    $sourceHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result = [ordered]@{
        Scenario = 'nativePersuasionVmInCurrentMapConversation'
        ProviderKind = 'Native MapConversationVM/PersuasionVM with visual-Harness-only temporary PersuasionTask and option delegate'
        ProcessId = $start.session.processId
        TargetHero = $overlayCharacters[0]
        InitialConversation = $conversation
        NativeAnswerListBeforeTask = $nativeAnswers.data
        VisibleNativeAnswerSeeded = $visibleNativeAnswers[0]
        NoActivePersuasion = $withoutTask.data
        HarnessSeed = $fixture.data
        PersuasionDetails = $persuasion.data
        VisibleNativePersuasionOption = $matchingOption[0]
        RepeatPersuasionDetails = $repeat.data
        ReadOnlyStable = $readOnlyStable
        VisibleCurrentPersuasionOptionAccepted = ($dialogueSelection.status -eq 'completed')
        DialogueSelectReceipt = $dialogueSelection
        StateAfterVisibleArgument = $afterSelection.state.context
        PersuasionAfterVisibleArgument = $persuasionAfterSelection.data
        FixtureHashBefore = $sourceHashBefore
        FixtureHashAfter = $sourceHashAfter
        FixtureUnchanged = ($sourceHashBefore -eq $sourceHashAfter)
        EngineFrames = @($frameConversation, $frameAnswerList, $framePersuasion, $frameAfterArgument)
    }
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $result.ProcessStopped = [bool]$stop.processStopped
    $result.AllGameProcessesStopped = -not [bool](Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)
    $result.Passed = ([bool]$result.ReadOnlyStable -and [bool]$result.VisibleCurrentPersuasionOptionAccepted -and [bool]$result.FixtureUnchanged -and [bool]$result.ProcessStopped -and [bool]$result.AllGameProcessesStopped)
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        $result | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath (Join-Path $tempPath $resultName) -Encoding UTF8
    }
    $result | ConvertTo-Json -Depth 18
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = $null
    if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) {
        try { $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $failedStep -FailureReason $_.Exception.ToString() }
        catch { $failureFrame = [ordered]@{ Captured = $false; Error = $_.Exception.Message } }
    }
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $failedStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $tempPath 'PersuasionDetails-Failure.json') -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path $sessionPath) {
        try { $session = Get-Content $sessionPath -Raw | ConvertFrom-Json; if ($session.status -ne 'stopped') { $null = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-final-stop") 30 } }
        catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
