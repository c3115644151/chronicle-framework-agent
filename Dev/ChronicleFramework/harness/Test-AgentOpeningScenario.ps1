#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'ChronicleEycDev-freshB-20261123092350-d1a1805e',
    [ValidateRange(0.25,5.0)][double]$ScenarioDays = 2.0,
    [ValidateRange(0.01,0.5)][double]$StepDays = 0.05,
    [ValidateRange(1,5)][int]$Repeats = 3,
    [ValidateRange(120,900)][int]$RepeatWallClockSeconds = 600,
    [ValidateSet('', 'bandit_start_defender_1', 'bandit_start_defender_2', 'bandit_start_defender_3', 'common_encounter_ultimatum', 'common_bandit_surrender_declined')][string]$Answer = '',
    [ValidateRange(0.05,2.0)][double]$AnswerFollowupDays = 0.5,
    [ValidateRange(0,120)][int]$WatchSeconds = 0,
    [string]$EncounterOption = '',
    [int]$TimeoutSeconds = 240
)

# Opening-scenario receipt: what the world hands a party at the very first decision, and whether the
# same checkpoint hands it the same thing twice. Loads the fixture from its own save, lets the original
# clock run in small steps, and stops at the first thing that asks the party to choose - a native menu,
# a conversation or an interruption. Nothing is executed: the receipt records the fork, its options and
# the party's condition, then the process is stopped and the save loaded again for the next repeat.
#
# This exists because the same save produced a bandit meeting in two runs and a quiet map in a third.
# A scenario whose fork is decided by the world cannot be judged from a single run, so the instrument
# measures the distribution instead of asserting that a meeting happens.
$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualOpeningScenario' }
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
$resultPath = Join-Path $runDirectory 'OpeningScenarioResult.json'
$progressPath = Join-Path $runDirectory 'OpeningScenarioProgress.log'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'opening-scenario-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Opening scenario fixture not found: $savePath" }
if (Get-Process -Name 'Bannerlord.BLSE.Standalone' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Write-Progress-Line([string]$Message) {
    # The stage collects stdout only when the whole script returns, so a stall would otherwise be
    # invisible: every step leaves a line behind in the run directory.
    Add-Content -LiteralPath $progressPath -Value ((Get-Date).ToString('HH:mm:ss') + '  ' + $Message) -Encoding utf8
}

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    # The CLI is a separate process, and a child that never returns would otherwise hang the whole
    # instrument: the wait is bounded here and the child is killed instead. A stall past the CLI's
    # own timeout means the container itself failed, which belongs in the receipt as a failure.
    $hardTimeoutSeconds = $effectiveTimeout + 90
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($HarnessPowerShell)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-File', $cli, $Action) + @($Arguments) + @('-TimeoutSeconds', "$effectiveTimeout", '-AsJson')) { $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($hardTimeoutSeconds * 1000)) {
        try { $process.Kill($true) } catch { }
        throw "Agent CLI '$Action' did not return within $hardTimeoutSeconds seconds."
    }
    $output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Get-State([string]$Tag, [int]$CommandTimeout = 0) {
    return Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-$Tag-$([Guid]::NewGuid().ToString('N'))") $CommandTimeout
}

function Get-Snapshot($Observation, [string]$Label) {
    $state = $Observation.state
    return [ordered]@{
        label = $Label
        campaignDay = [double]$state.campaignDay
        gameState = [string]$state.context.gameState
        menuId = [string]$state.context.menuId
        timeControlMode = [string]$state.context.timeControlMode
        encounterActive = [bool]$state.context.encounterActive
        encounteredPartyId = [string]$state.context.encounteredPartyId
        heroHitPoints = [int]$state.party.heroHitPoints
        heroMaxHitPoints = [int]$state.party.heroMaxHitPoints
        gold = [int]$state.economy.gold
        members = [int]$state.party.members
        healthy = [int]$state.party.healthy
        wounded = [int]$state.party.wounded
        morale = [int]$state.party.morale
        food = [double]$state.party.food
        foodInventory = [int]$state.party.foodInventory
        dailyWage = [int]$state.party.dailyWage
        captivity = [bool]$state.context.captivity
        isMoving = [bool]$state.party.isMoving
    }
}

function Test-ChoiceOpen($Observation) {
    $context = $Observation.state.context
    if (-not [string]::IsNullOrWhiteSpace([string]$context.menuId)) { return $true }
    # The observer always emits a conversation and a mapIncident object, so their presence says
    # nothing; only their content does. A fork is a menu, or a sentence the party has to answer.
    $conversation = $context.conversation
    if ($null -ne $conversation) {
        if (-not [string]::IsNullOrWhiteSpace([string]$conversation.sentenceText)) { return $true }
        if ($null -ne $conversation.options -and @($conversation.options).Count -gt 0) { return $true }
    }
    if ($null -ne $context.mapIncident -and [bool]$context.mapIncident.active) { return $true }
    return $false
}

function Get-Fork($Observation) {
    $context = $Observation.state.context
    $conversation = $context.conversation
    $options = @()
    if ($null -ne $conversation -and $null -ne $conversation.options) {
        $options = @($conversation.options | ForEach-Object {
            [ordered]@{
                id = [string]$_.id
                textId = [string]$_.textId
                text = [string]$_.text
                clickable = [bool]$_.clickable
            }
        })
    }
    # The option surface lives at the top of the state, not under context: the map menu is a
    # MapMenu on the campaign map, so context carries only its id. Clickable means both flags.
    $menuOptionsAll = @($Observation.state.availableMenuOptions | ForEach-Object {
        [ordered]@{
            id = [string]$_.id
            text = [string]$_.text
            available = [bool]$_.available
            enabled = [bool]$_.enabled
            isLeave = [bool]$_.isLeave
        }
    })
    $menuOptions = @($menuOptionsAll | Where-Object { $_.available -and $_.enabled })
    $fork = [ordered]@{
        menuId = [string]$context.menuId
        encounterActive = [bool]$context.encounterActive
        encounteredPartyId = [string]$context.encounteredPartyId
        conversation = $null
        options = $options
        menuOptions = $menuOptions
        menuOptionsAll = $menuOptionsAll
    }
    if ($null -ne $conversation) {
        $fork.conversation = [ordered]@{
            characterId = [string]$conversation.characterId
            characterName = [string]$conversation.characterName
            sentenceText = [string]$conversation.sentenceText
        }
    }
    return $fork
}

function Get-Probe([string]$Action, [string]$Tag, [string[]]$Arguments = @()) {
    # A probe records what the protocol does with a verb in the state the world put us in;
    # a rejection is the measurement, so it must not abort the run.
    try {
        $receipt = Invoke-AgentCli $Action (@('-CommandId', "$commandPrefix-$Tag") + $Arguments) 60
        return [ordered]@{ status = [string]$receipt.status; error = [string]$receipt.error }
    }
    catch {
        return [ordered]@{ status = 'rejected'; error = ($_.Exception.Message -split '\r?\n')[0] }
    }
}

function Get-ForkKind($Fork, [bool]$ScenarioExhausted) {
    $characterId = [string]$Fork.conversation.characterId
    if (-not [string]::IsNullOrWhiteSpace($characterId)) {
        if ($characterId -match 'bandit|looter|raider|raider|sea_raiders|deserter') { return 'bandit-conversation' }
        return 'conversation'
    }
    if ([string]$Fork.menuId -like 'encounter*') { return 'encounter-menu' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Fork.menuId)) { return 'other-menu' }
    if ($ScenarioExhausted) { return 'no-fork' }
    return 'none'
}

$runs = [System.Collections.Generic.List[object]]::new()
$assertions = [ordered]@{}
$failure = $null
try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $steps = [int][Math]::Ceiling($ScenarioDays / $StepDays)
    for ($repeat = 1; $repeat -le $Repeats; $repeat++) {
        Write-Progress-Line "repeat ${repeat}: loading $LoadSaveName"
        $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
        $record = [ordered]@{
            repeat = $repeat
            stepsRequested = $steps
            stepsTaken = 0
            scenarioExhausted = $false
            answer = $Answer
            answerReceipt = $null
            answeredOptionWasOffered = $false
            answerAccepted = $false
            afterAnswer = [System.Collections.Generic.List[object]]::new()
            secondFork = $null
            secondForkKind = ''
            dialogueContinues = [System.Collections.Generic.List[object]]::new()
            watch = [System.Collections.Generic.List[object]]::new()
            encounterOption = $EncounterOption
            encounterOptionWasClickable = $null
            encounterOptionReceipt = $null
            reachedCampaignDay = 0.0
            forkKind = ''
            start = $null
            fork = $null
            timeline = [System.Collections.Generic.List[object]]::new()
        }
        $initial = Get-State "r$repeat-start"
        if ([string]$initial.state.context.gameState -ne 'MapState') { throw "Repeat #$repeat loaded into '$($initial.state.context.gameState)' instead of the campaign map." }
        $record.start = Get-Snapshot $initial "r$repeat-start"
        $deadline = [DateTime]::UtcNow.AddSeconds($RepeatWallClockSeconds)
        for ($step = 1; $step -le $steps; $step++) {
            if ([DateTime]::UtcNow -gt $deadline) { throw "Repeat #$repeat did not reach a choice within $RepeatWallClockSeconds seconds." }
            $observed = Get-State "r$repeat-p$step" 60
            Write-Progress-Line "repeat ${repeat} step ${step}: day $([double]$observed.state.campaignDay) hp $([int]$observed.state.party.heroHitPoints)"
            $record.stepsTaken = $step
            $record.timeline.Add((Get-Snapshot $observed "r$repeat-p$step"))
            $record.reachedCampaignDay = [double]$observed.state.campaignDay
            if (Test-ChoiceOpen $observed) {
                $record.fork = Get-Fork $observed
                break
            }
            if ($step -ge $steps) { $record.scenarioExhausted = $true; break }
            $advance = Invoke-AgentCli 'advance' @('-Days', $StepDays.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture), '-CommandId', "$commandPrefix-r$repeat-step-$step") -CommandTimeout 120
            if ($advance.status -notin @('completed', 'accepted')) { throw "Native advance stopped at step $step of repeat #${repeat}: status=$($advance.status) error=$($advance.error)" }
        }
        $record.forkKind = Get-ForkKind $record.fork ([bool]$record.scenarioExhausted)
        if (-not [string]::IsNullOrWhiteSpace($Answer)) {
            # Answering the fork is the other half of the measurement: the world's answer to the one move
            # the model is offered, sampled the way the walk to the fork was.
            if (-not $record.fork) { throw "Repeat #${repeat} was asked to answer '$Answer' but never reached a fork." }
            $record.answeredOptionWasOffered = @($record.fork.options | Where-Object { [string]$_.id -eq $Answer }).Count -gt 0
            Write-Progress-Line "repeat ${repeat}: answering $Answer (offered: $($record.answeredOptionWasOffered))"
            $answerReceipt = Invoke-AgentCli 'dialogueSelect' @('-OptionId', $Answer, '-CommandId', "$commandPrefix-r$repeat-answer") -CommandTimeout 120
            $record.answerReceipt = [ordered]@{ status = [string]$answerReceipt.status; error = [string]$answerReceipt.error }
            $record.answerAccepted = ([string]$answerReceipt.status -eq 'completed')
            $followupSteps = [int][Math]::Ceiling($AnswerFollowupDays / $StepDays)
            for ($followup = 1; $followup -le $followupSteps; $followup++) {
                $sample = Get-State "r$repeat-a$followup" 60
                $snapshot = Get-Snapshot $sample "r$repeat-a$followup"
                $record.afterAnswer.Add($snapshot)
                $options = @()
                if ($null -ne $sample.state.context.conversation -and $null -ne $sample.state.context.conversation.options) {
                    $options = @($sample.state.context.conversation.options)
                }
                $line = [string]$sample.state.context.conversation.sentenceText
                Write-Progress-Line "repeat ${repeat} answer step ${followup}: day $($snapshot.campaignDay) hp $($snapshot.heroHitPoints) state $($snapshot.gameState) menu $($snapshot.menuId) options $($options.Count) captivity $($snapshot.captivity) line=$line"
                $answeredOptionStillListed = @($options | Where-Object { [string]$_.id -eq $Answer }).Count -gt 0
                if ($options.Count -gt 0 -and -not $answeredOptionStillListed) {
                    $record.secondFork = Get-Fork $sample
                    $record.secondForkKind = Get-ForkKind $record.secondFork $false
                    break
                }
                if ([string]$sample.state.context.gameState -ne 'MapState') { break }
                # A menu with clickable options is the next decision point, whether or not an Encounter
                # is running; the Encounter meeting menu alone is not, it is just where the line is read.
                if (@($sample.state.availableMenuOptions | Where-Object { [bool]$_.available -and [bool]$_.enabled }).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshot.menuId)) {
                    $record.secondFork = Get-Fork $sample
                    $record.secondForkKind = Get-ForkKind $record.secondFork $false
                    break
                }
                # A Native conversation line without options is a click, not a decision: keep it moving
                # so the sample lands on the option set the game actually offers next.
                if ($null -ne $sample.state.context.conversation -and $options.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($line)) {
                    $continueReceipt = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$commandPrefix-r$repeat-a$followup") -CommandTimeout 120
                    $record.dialogueContinues.Add([ordered]@{ step = $followup; status = [string]$continueReceipt.status; error = [string]$continueReceipt.error })
                    if ($continueReceipt.status -notin @('completed', 'accepted')) { throw "Native dialogue continue failed after answering at step $followup of repeat #${repeat}: status=$($continueReceipt.status) error=$($continueReceipt.error)" }
                    continue
                }
                if ($snapshot.encounterActive) {
                    $record.secondForkProbes = [ordered]@{
                        menu = (Get-Probe 'menu' "r$repeat-probe-menu")
                        battleSkip = (Get-Probe 'battleSkip' "r$repeat-probe-battle")
                        dialogueSelect = (Get-Probe 'dialogueSelect' "r$repeat-probe-dialogue" @('-OptionId', $Answer))
                        menuSelect = (Get-Probe 'menuSelect' "r$repeat-probe-menuselect" @('-MenuId', 'encounter', '-OptionId', 'str_order_attack'))
                    }
                    $framePath = Join-Path $runDirectory "OpeningScenario-r$repeat-second-fork.bmp"
                    $frameReceipt = Get-Probe 'captureFrame' "r$repeat-probe-frame" @('-OutputPath', $framePath)
                    $record.secondForkFrame = [ordered]@{ path = $framePath; status = [string]$frameReceipt.status; error = [string]$frameReceipt.error; bytes = if (Test-Path -LiteralPath $framePath) { (Get-Item -LiteralPath $framePath).Length } else { 0 } }
                    $record.secondFork = Get-Fork $sample
                    $record.secondForkKind = Get-ForkKind $record.secondFork $false
                    break
                }
                $advance = Invoke-AgentCli 'advance' @('-Days', $StepDays.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture), '-CommandId', "$commandPrefix-r$repeat-a$followup") -CommandTimeout 120
                if ($advance.status -notin @('completed', 'accepted')) { throw "Native advance stopped after answering at step $followup of repeat #${repeat}: status=$($advance.status) error=$($advance.error)" }
            }
        }
        if ($null -ne $record.secondFork -and -not [string]::IsNullOrWhiteSpace([string]$record.secondFork.menuId) -and @($record.secondFork.menuOptions).Count -eq 0) {
            # The encounter menu is filled by the map state's own tick, so the first sample can land
            # before its options exist. Settle before declaring the surface empty.
            for ($settle = 1; $settle -le 6; $settle++) {
                Start-Sleep -Milliseconds 500
                $settled = Get-State "r$repeat-s$settle" 60
                $settledOptions = @($settled.state.availableMenuOptions | Where-Object { [bool]$_.available -and [bool]$_.enabled })
                Write-Progress-Line "repeat ${repeat} settle ${settle}: menu $($settled.state.context.menuId) options $($settledOptions.Count)"
                if ($settledOptions.Count -gt 0) {
                    $record.secondFork = Get-Fork $settled
                    $record.secondForkKind = Get-ForkKind $record.secondFork $false
                    break
                }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($EncounterOption) -and $null -ne $record.secondFork -and [string]$record.secondFork.menuId -eq 'encounter') {
            # In a cornered encounter the game offers exactly one clickable option. Clicking it is how
            # the scenario reaches captivity without a model, so the receipt says whether the surface
            # the Harness published and the surface the game accepts agree.
            $record.encounterOptionWasClickable = @($record.secondFork.menuOptions | Where-Object { [string]$_.id -eq $EncounterOption }).Count -gt 0
            Write-Progress-Line "repeat ${repeat}: clicking encounter option $EncounterOption (listed clickable: $($record.encounterOptionWasClickable))"
            $encounterReceipt = Get-Probe 'menuSelect' "r$repeat-encounter-option" @('-MenuId', 'encounter', '-OptionId', $EncounterOption)
            $record.encounterOptionReceipt = [ordered]@{ status = [string]$encounterReceipt.status; error = [string]$encounterReceipt.error }
            Write-Progress-Line "repeat ${repeat}: encounter option $EncounterOption -> $($record.encounterOptionReceipt.status) $($record.encounterOptionReceipt.error)"
        }
        for ($watch = 1; $watch -le $WatchSeconds; $watch++) {
            # After the fork is answered there is sometimes nothing to click: the world finishes the scene
            # on its own tick. Watching records which way it went without acting.
            Start-Sleep -Seconds 1
            $watched = Get-State "r$repeat-w$watch" 60
            $record.watch.Add((Get-Snapshot $watched "r$repeat-w$watch"))
            Write-Progress-Line "repeat ${repeat} watch ${watch}: state $($watched.state.context.gameState) menu $($watched.state.context.menuId) hp $($watched.state.party.heroHitPoints) captivity $($watched.state.context.captivity)"
            if ([string]$watched.state.context.gameState -ne 'MapState') { break }
        }
        Write-Progress-Line "repeat ${repeat}: fork $($record.forkKind) at day $($record.reachedCampaignDay); stopping"
        $stop = Invoke-AgentCli 'stop' @() -CommandTimeout 120
        $record.processStopped = [bool]$stop.processStopped
        $exitDeadline = [DateTime]::UtcNow.AddSeconds(90)
        while ($start -and (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $exitDeadline) { Start-Sleep -Milliseconds 500 }
        $runs.Add($record)
        $start = $null
        Start-Sleep -Seconds 2
    }
} catch {
    $failure = $_
}

if ($start) { try { Invoke-AgentCli 'stop' @() -CommandTimeout 120 | Out-Null } catch { if (-not $failure) { $failure = $_ } } }
if ($previousHarnessMode) { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode } else { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }

$forkKinds = @($runs | ForEach-Object { [string]$_.forkKind })
$conversationRepeats = @($runs | Where-Object { [string]$_.forkKind -eq 'bandit-conversation' })
$assertions['FixtureUnchanged'] = ((Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash -eq $fixtureHashBefore)
$assertions['AllRepeatsRecorded'] = ($runs.Count -eq $Repeats)
$assertions['EveryRepeatReachedAVerdict'] = @($runs | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.forkKind) }).Count -eq 0
# The native fork must carry at least two clickable sentences; one would mean the conversation was
# captured between two ticks rather than at the moment the party has to answer.
$assertions['ConversationForksCarryNativeOptions'] = @($conversationRepeats | Where-Object { @($_.fork.options | Where-Object { [bool]$_.clickable }).Count -lt 2 }).Count -eq 0
$assertions['EveryRepeatStoppedItsProcess'] = @($runs | Where-Object { -not [bool]$_.processStopped }).Count -eq 0
$assertions['EncounterOptionWasClickableWhenAsked'] = if ([string]::IsNullOrWhiteSpace($EncounterOption)) { $true } else { @($runs | Where-Object { -not [bool]$_.encounterOptionWasClickable }).Count -eq 0 }
$assertions['AnswerAcceptedWhenAsked'] = if ([string]::IsNullOrWhiteSpace($Answer)) { $true } else { @($runs | Where-Object { -not [bool]$_.answerAccepted }).Count -eq 0 }
$failedAssertions = @($assertions.Keys | Where-Object { -not $assertions[$_] })

$receipt = [ordered]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    Fixture = $LoadSaveName
    FixtureSha256 = $fixtureHashBefore
    Parameters = [ordered]@{ ScenarioDays = $ScenarioDays; StepDays = $StepDays; Repeats = $Repeats; RepeatWallClockSeconds = $RepeatWallClockSeconds; Answer = $Answer; AnswerFollowupDays = $AnswerFollowupDays; WatchSeconds = $WatchSeconds; EncounterOption = $EncounterOption }
    ForkKinds = $forkKinds
    Repeats = $runs
    Assertions = $assertions
    FailedAssertions = $failedAssertions
    Passed = ($failedAssertions.Count -eq 0 -and -not $failure)
    ModelRequests = 0
}
if ($failure) { $receipt['Error'] = $failure.Exception.Message }
$receiptJson = ConvertTo-Json -InputObject $receipt -Depth 10
Set-Content -LiteralPath $resultPath -Value $receiptJson -Encoding UTF8

$runs | ForEach-Object { "repeat {0}: {1} steps, day {2}, fork {3}, hp {4}/{5}, gold {6}, healthy {7}, wounded {8}" -f $_.repeat, $_.stepsTaken, [Math]::Round($_.reachedCampaignDay, 3), $_.forkKind, $_.timeline[$_.timeline.Count - 1].heroHitPoints, $_.timeline[$_.timeline.Count - 1].heroMaxHitPoints, $_.timeline[$_.timeline.Count - 1].gold, $_.timeline[$_.timeline.Count - 1].healthy, $_.timeline[$_.timeline.Count - 1].wounded }
"forkKinds=$($forkKinds -join ',') passed=$($receipt.Passed) failed=$($failedAssertions -join ',') receipt=$resultPath"
if ($failure) { throw $failure }
if ($failedAssertions.Count -gt 0) { throw "Opening scenario assertions failed: $($failedAssertions -join ',')" }
