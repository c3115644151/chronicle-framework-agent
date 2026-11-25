#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'ChronicleEycDev-freshB-20261123092350-d1a1805e',
    [ValidateRange(0.25,5.0)][double]$ScenarioDays = 2.0,
    [ValidateRange(0.01,0.5)][double]$StepDays = 0.05,
    [ValidateRange(1,5)][int]$Repeats = 3,
    [ValidateRange(120,900)][int]$RepeatWallClockSeconds = 600,
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
    $fork = [ordered]@{
        menuId = [string]$context.menuId
        encounterActive = [bool]$context.encounterActive
        encounteredPartyId = [string]$context.encounteredPartyId
        conversation = $null
        options = $options
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
$failedAssertions = @($assertions.Keys | Where-Object { -not $assertions[$_] })

$receipt = [ordered]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    Fixture = $LoadSaveName
    FixtureSha256 = $fixtureHashBefore
    Parameters = [ordered]@{ ScenarioDays = $ScenarioDays; StepDays = $StepDays; Repeats = $Repeats; RepeatWallClockSeconds = $RepeatWallClockSeconds }
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
