#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180,
    [int]$EncounterWaitSeconds = 90
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$tempPath = $env:CHRONICLE_HARNESS_TEMP
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualEncounterEscape' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath 'EncounterEscapeResult.json' } else { Join-Path $runDirectory 'EncounterEscapeResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'encounter-escape-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$currentStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Encounter escape fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'Test-AgentSupport.ps1')

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Capture-EngineFrame([string]$Path, [string]$Suffix) {
    $receipt = Invoke-AgentCli 'captureFrame' @('-OutputPath', $Path, '-CommandId', "$prefix-$Suffix") 30
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    $exists = Test-Path -LiteralPath $Path
    $length = if ($exists) { (Get-Item -LiteralPath $Path).Length } else { 0 }
    if ($receipt.status -ne 'completed' -or -not $exists -or $length -lt 4096)
        { throw "Native Encounter escape frame '$Path' was not captured (receipt='$($receipt.status)', exists=$exists, bytes=$length)." }
}

function Wait-ForNativeBanditEncounter([int]$ProcessId, [string]$PartyId) {
    $deadline = [DateTime]::UtcNow.AddSeconds($EncounterWaitSeconds)
    $consecutiveTimeouts = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-meeting-poll-$([Guid]::NewGuid().ToString('N'))") 8; $consecutiveTimeouts = 0 }
        catch {
            if ($_.Exception.Message -notmatch 'timed out after') { throw }
            $consecutiveTimeouts++
            if ($consecutiveTimeouts -ge 3) { throw 'Game stopped answering while waiting for the Native Bandit meeting/Encounter.' }
            if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited while waiting for the Native Bandit meeting/Encounter.' }
            continue
        }
        if ([bool]$state.state.context.encounterActive -and $state.state.context.encounteredPartyId -eq $PartyId) {
            if ($state.state.context.menuId -eq 'encounter') { return [ordered]@{ State = $state; Meeting = $null; FightChoice = $null } }
            if ($state.state.context.conversation) { return [ordered]@{ State = $null; Meeting = $state; FightChoice = $null } }
        }
        if ($state.state.context.captivity) { throw 'Player was captured before the escape outcome test reached the Encounter menu.' }
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited while waiting for the Native Bandit meeting/Encounter.' }
        Start-Sleep -Milliseconds 250
    }
    throw 'The approaching Native Bandit did not open the expected meeting or Encounter.'
}

function Enter-NativeEncounterFromBanditMeeting([object]$Meeting, [int]$ProcessId, [string]$PartyId, [string]$Suffix) {
    $fightOption = @($Meeting.state.context.conversation.options | Where-Object { $_.id -eq 'bandit_start_defender_1' -and $_.clickable } | Select-Object -First 1)
    if ($fightOption.Count -ne 1) { throw "Native Bandit meeting lacks its current clickable Fight option. Options=$(($Meeting.state.context.conversation.options | ForEach-Object id) -join ',')" }
    $fightChoice = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'bandit_start_defender_1', '-CommandId', "$prefix-$Suffix-bandit-fight") 15
    if ($fightChoice.status -ne 'completed') { throw "Native Bandit Fight option failed: $($fightChoice.error)" }

    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $deadline) {
        $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-$Suffix-encounter-poll-$([Guid]::NewGuid().ToString('N'))") 8
        if ($state.state.context.menuId -eq 'encounter' -and [bool]$state.state.context.encounterActive -and $state.state.context.encounteredPartyId -eq $PartyId)
            { return [ordered]@{ State = $state; FightChoice = $fightChoice } }
        $conversation = $state.state.context.conversation
        if ($conversation -and @($conversation.options | Where-Object clickable).Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$conversation.sentenceText)) {
            $continue = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-$Suffix-bandit-fight-continue") 10
            if ($continue.status -ne 'completed') { throw "Native Fight response line could not continue: $($continue.error)" }
        }
        elseif ($conversation -and @($conversation.options | Where-Object clickable).Count -gt 0) { throw 'Unexpected new Native Bandit choice appeared after selecting Fight.' }
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before opening the Native Encounter menu.' }
        Start-Sleep -Milliseconds 150
    }
    throw 'Native Bandit Fight did not reach its Encounter menu.'
}

function Invoke-NativeEscapeTrial([ValidateSet('Reject','Accept')][string]$Choice) {
    $suffix = $Choice.ToLowerInvariant()
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    try {
        $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-$suffix-initial")
        if ($initial.state.context.gameState -ne 'MapState' -or $initial.state.context.encounterActive -or $initial.state.context.captivity)
            { throw "$Choice trial must start on a free Campaign Map." }

        $seed = Invoke-AgentCli 'harnessSeedTryGetAwayFixture' @('-CommandId', "$prefix-$suffix-party-fixture") 30
        if ($seed.status -ne 'completed' -or [int]$seed.data.healthyNonHeroesAfter -lt 9 -or [int]$seed.data.grainAfter -lt 20)
            { throw "$Choice trial failed to seed the minimum Native escape-test Party and merchandise roster." }
        $banditFixture = Invoke-AgentCli 'harnessPrepareSafePassageFixture' @('-CommandId', "$prefix-$suffix-bandit-fixture") 30
        if ($banditFixture.status -ne 'completed' -or -not [bool]$banditFixture.data.hostile -or [string]::IsNullOrWhiteSpace([string]$banditFixture.data.partyId))
            { throw "$Choice trial failed to create its Native hostile Bandit faction." }

        $approach = Invoke-AgentCli 'moveToPoint' @(
            '-X', ([double]$banditFixture.data.playerApproachPoint.x).ToString([Globalization.CultureInfo]::InvariantCulture),
            '-Y', ([double]$banditFixture.data.playerApproachPoint.y).ToString([Globalization.CultureInfo]::InvariantCulture),
            '-Surface', 'land', '-CommandId', "$prefix-$suffix-approach") 30
        if ($approach.status -ne 'completed' -or $approach.timeControlMode -ne 'StoppablePlay')
            { throw "$Choice trial did not start Native point navigation under its ordinary StoppablePlay mode." }

        $meeting = Wait-ForNativeBanditEncounter ([int]$start.session.processId) ([string]$banditFixture.data.partyId)
        $meetingFrame = Join-Path $frameRoot "encounter-escape-$suffix-bandit-meeting.bmp"
        if ($meeting.Meeting) {
            Capture-EngineFrame $meetingFrame "$suffix-bandit-meeting-frame"
            $encounterResult = Enter-NativeEncounterFromBanditMeeting $meeting.Meeting ([int]$start.session.processId) ([string]$banditFixture.data.partyId) $suffix
            $encounter = $encounterResult.State
            $fightChoice = $encounterResult.FightChoice
        }
        else {
            $encounter = $meeting.State
            $fightChoice = $null
            Capture-EngineFrame $meetingFrame "$suffix-encounter-entry-frame"
        }
        if ($encounter.state.context.menuId -ne 'encounter' -or -not [bool]$encounter.state.context.encounterActive)
            { throw "$Choice trial did not reach the Native Encounter menu." }

        $encounterDiag = Invoke-AgentCli 'harnessTryGetAwayDiagnostics' @('-CommandId', "$prefix-$suffix-encounter-diagnostics") 30
        if ($encounterDiag.status -ne 'completed') { throw "$Choice trial lacked Native precondition diagnostics for Try to get away." }
        $escapeOption = @($encounter.state.availableMenuOptions | Where-Object { $_.id -eq 'leave_soldiers_behind' -and $_.available -and $_.enabled } | Select-Object -First 1)
        if ($escapeOption.Count -ne 1 -or -not [bool]$encounterDiag.data.canTryToGetAway -or [int]$encounterDiag.data.nativeTroopsSacrificedForTry -lt 0)
            { throw "$Choice trial's Native Encounter lacks an enabled Try-to-get-away option. Diagnostics=$($encounterDiag.data | ConvertTo-Json -Compress)" }

        $encounterFrame = Join-Path $frameRoot "encounter-escape-$suffix-before-menu.bmp"
        $warningFrame = Join-Path $frameRoot "encounter-escape-$suffix-warning.bmp"
        $outcomeFrame = Join-Path $frameRoot "encounter-escape-$suffix-outcome.bmp"
        Capture-EngineFrame $encounterFrame "$suffix-before-menu-frame"
        $openWarning = Invoke-AgentCli 'menuSelect' @('-MenuId', 'encounter', '-OptionId', 'leave_soldiers_behind', '-CommandId', "$prefix-$suffix-open-warning") 20
        if ($openWarning.status -ne 'completed') { throw "Native Try-to-get-away option was rejected: $($openWarning.error)" }

        $warning = Invoke-AgentCli 'state' @('-CommandId', "$prefix-$suffix-warning-state")
        if ($warning.state.context.menuId -ne 'try_to_get_away')
            { throw "$Choice trial did not enter the Native Try-to-get-away warning menu; got '$($warning.state.context.menuId)'." }
        $warningDiag = Invoke-AgentCli 'harnessTryGetAwayDiagnostics' @('-CommandId', "$prefix-$suffix-warning-diagnostics") 30
        $nativeEscapeObservation = $warning.state.context.encounterEscape
        if (-not $nativeEscapeObservation -or
            -not [bool]$nativeEscapeObservation.canTryToGetAway -or
            [string]$nativeEscapeObservation.menuText -ne [string]$warningDiag.data.menuText -or
            [int]$nativeEscapeObservation.nativeTroopsSacrificedForTry -ne [int]$warningDiag.data.nativeTroopsSacrificedForTry -or
            [int]$nativeEscapeObservation.healthyNonHeroMembers -ne [int]$warningDiag.data.healthyNonHeroCount) {
            throw "$Choice trial did not expose the exact current Native Try-to-get-away warning and sacrifice estimate in the normal Agent observation."
        }
        Capture-EngineFrame $warningFrame "$suffix-warning-frame"
        $warningOptions = @($warning.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled })
        $acceptOption = @($warningOptions | Where-Object { $_.id -eq 'try_to_get_away_accept' })
        $rejectOption = @($warningOptions | Where-Object { $_.id -eq 'try_to_get_away_reject' })
        if ($acceptOption.Count -ne 1 -or $rejectOption.Count -ne 1 -or -not [bool]$warningDiag.data.canTryToGetAway)
            { throw "$Choice trial warning lacks the currently enabled Native Accept/Reject options or positive TroopSacrificeModel result." }

        if ($Choice -eq 'Reject') {
            $rejectReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'try_to_get_away', '-OptionId', 'try_to_get_away_reject', '-CommandId', "$prefix-reject-choice") 20
            if ($rejectReceipt.status -ne 'completed') { throw "Native escape rejection was not accepted: $($rejectReceipt.error)" }
            $after = Invoke-AgentCli 'state' @('-CommandId', "$prefix-reject-after")
            $afterDiag = Invoke-AgentCli 'harnessTryGetAwayDiagnostics' @('-CommandId', "$prefix-reject-after-diagnostics") 30
            Capture-EngineFrame $outcomeFrame 'reject-outcome-frame'
            $nativeNoChange = ([int]$warningDiag.data.memberCount -eq [int]$afterDiag.data.memberCount -and
                [int]$warningDiag.data.grainCount -eq [int]$afterDiag.data.grainCount -and
                [int]$warningDiag.data.gold -eq [int]$afterDiag.data.gold -and
                [double]$warningDiag.data.campaignDay -eq [double]$afterDiag.data.campaignDay -and
                [string]$warningDiag.data.timeControlMode -eq [string]$afterDiag.data.timeControlMode)
            $stillEncountered = ([bool]$after.state.context.encounterActive -and $after.state.context.menuId -eq 'encounter' -and $after.state.context.encounteredPartyId -eq $banditFixture.data.partyId)
            $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-reject-stop") 30
            $hashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
            return [ordered]@{
                Choice = $Choice; ProcessId = $start.session.processId; PartyFixture = $seed.data; BanditFixture = $banditFixture.data
                PlayerApproach = $approach; BanditFightDialogueChoice = $fightChoice; EncounterFrame = $encounterFrame
                EncounterDiagnostic = $encounterDiag.data; WarningDiagnostic = $warningDiag.data
                CurrentWarningText = $warningDiag.data.menuText; NativeEscapeObservation = $nativeEscapeObservation
                VisibleOptions = @($warningOptions | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } })
                NativeDecision = $rejectReceipt; After = $after.state; AfterDiagnostic = $afterDiag.data
                NoWorldStateChangesOnReject = $nativeNoChange; ReturnedToOriginalEncounter = $stillEncountered
                EngineFrames = @($meetingFrame,$encounterFrame,$warningFrame,$outcomeFrame)
                SourceFixtureUnchanged = ($fixtureHashBefore -eq $hashAfter); ProcessStopped = [bool]$stop.processStopped
                Passed = ($nativeNoChange -and $stillEncountered -and $fixtureHashBefore -eq $hashAfter -and [bool]$stop.processStopped)
            }
        }

        $acceptReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'try_to_get_away', '-OptionId', 'try_to_get_away_accept', '-CommandId', "$prefix-accept-choice") 20
        if ($acceptReceipt.status -ne 'completed') { throw "Native escape confirmation was not accepted: $($acceptReceipt.error)" }
        $debrief = Invoke-AgentCli 'state' @('-CommandId', "$prefix-accept-debrief")
        if ($debrief.state.context.menuId -ne 'try_to_get_away_debrief')
            { throw "Native escape confirmation did not lead to its debrief; got '$($debrief.state.context.menuId)'." }
        $afterDiag = Invoke-AgentCli 'harnessTryGetAwayDiagnostics' @('-CommandId', "$prefix-accept-after-diagnostics") 30
        Capture-EngineFrame $outcomeFrame 'accept-debrief-frame'
        $postOptions = @($debrief.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled })
        $continueOption = @($postOptions | Where-Object { $_.id -eq 'try_to_get_away_continue' })
        $nativeExpectedLoss = [int]$warningDiag.data.nativeTroopsSacrificedForTry
        $actualTroopLoss = [int]$warningDiag.data.healthyNonHeroCount - [int]$afterDiag.data.healthyNonHeroCount
        $grainBefore = [int]$warningDiag.data.grainCount
        $expectedGrainLoss = [Math]::Floor($grainBefore * 0.15)
        $actualGrainLoss = $grainBefore - [int]$afterDiag.data.grainCount
        $nativeLossMatches = ($actualTroopLoss -eq $nativeExpectedLoss)
        $grainLossMatches = ($actualGrainLoss -eq $expectedGrainLoss)
        $continueReceipt = $null
        $finalState = $null
        if ($continueOption.Count -eq 1) {
            $continueReceipt = Invoke-AgentCli 'menuSelect' @('-MenuId', 'try_to_get_away_debrief', '-OptionId', 'try_to_get_away_continue', '-CommandId', "$prefix-continue-debrief") 20
            if ($continueReceipt.status -ne 'completed') { throw "Native escape debrief Continue was rejected: $($continueReceipt.error)" }
            $finalState = Invoke-AgentCli 'state' @('-CommandId', "$prefix-after-debrief")
        }
        $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-accept-stop") 30
        $hashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
        return [ordered]@{
            Choice = $Choice; ProcessId = $start.session.processId; PartyFixture = $seed.data; BanditFixture = $banditFixture.data
            PlayerApproach = $approach; BanditFightDialogueChoice = $fightChoice; EncounterDiagnostic = $encounterDiag.data
            WarningDiagnostic = $warningDiag.data; NativeEscapeObservation = $nativeEscapeObservation; CurrentWarningText = $warningDiag.data.menuText
            VisibleDecisionOptions = @($warningOptions | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } })
            AcceptReceipt = $acceptReceipt; AfterDiagnostic = $afterDiag.data; Debrief = $debrief.state
            ExpectedNativeTroopLoss = $nativeExpectedLoss; ActualHealthyTroopLoss = $actualTroopLoss; NativeLossMatches = $nativeLossMatches
            ExpectedGrainLoss = $expectedGrainLoss; ActualGrainLoss = $actualGrainLoss; MerchandiseLossMatches = $grainLossMatches
            DebriefContinueAvailable = ($continueOption.Count -eq 1); DebriefContinue = $continueReceipt; AfterContinueState = if ($finalState) { $finalState.state } else { $null }
            EngineFrames = @($meetingFrame,$encounterFrame,$warningFrame,$outcomeFrame)
            SourceFixtureUnchanged = ($fixtureHashBefore -eq $hashAfter); ProcessStopped = [bool]$stop.processStopped
            Passed = ($nativeLossMatches -and $grainLossMatches -and $continueOption.Count -eq 1 -and $fixtureHashBefore -eq $hashAfter -and [bool]$stop.processStopped)
        }
    }
    finally {
        if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' @('-CommandId', "$prefix-$suffix-finally-stop") 30 | Out-Null } catch { } }
    }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $reject = Invoke-NativeEscapeTrial 'Reject'
    if (-not $reject.Passed) { throw "Native Try-to-get-away Reject branch failed: $($reject | ConvertTo-Json -Depth 8 -Compress)" }
    $accept = Invoke-NativeEscapeTrial 'Accept'
    $sourceHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $processesStopped = -not [bool](Get-Process -Name Bannerlord -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        ProviderKind = 'Native Try-to-get-away Encounter menu, warning confirmation, and debrief; separate disposable Campaign runs'
        Reject = $reject
        Accept = $accept
        SourceFixtureHashBefore = $fixtureHashBefore
        SourceFixtureHashAfter = $sourceHashAfter
        SourceFixtureUnchanged = ($fixtureHashBefore -eq $sourceHashAfter)
        AllGameProcessesStopped = $processesStopped
        Passed = ([bool]$reject.Passed -and [bool]$accept.Passed -and $fixtureHashBefore -eq $sourceHashAfter -and $processesStopped)
    }
    $json = $result | ConvertTo-Json -Depth 18
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $currentStep -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $currentStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tempPath 'EncounterEscapeFailure.json') -Encoding UTF8
    }
    throw
}
finally {
    if (Test-Path $sessionPath) {
        try {
            $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
            if ($session.status -ne 'stopped') { $null = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-final-stop") 30 }
        }
        catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
