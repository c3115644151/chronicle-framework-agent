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
$runDirectory = if ($tempPath) { Split-Path -Parent $tempPath } else { Join-Path $PSScriptRoot 'TestResults\ManualEncounterSurrender' }
$frameRoot = if ($tempPath) { $tempPath } else { $runDirectory }
$resultPath = if ($tempPath) { Join-Path $tempPath 'EncounterSurrenderResult.json' } else { Join-Path $runDirectory 'EncounterSurrenderResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$prefix = 'encounter-surrender-' + (Get-Date -Format 'yyyyMMddHHmmssfff')
$currentStep = 'preflight'

if (-not (Test-Path -LiteralPath $savePath)) { throw "Encounter surrender fixture not found: $LoadSaveName" }
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
        { throw "Native Encounter frame '$Path' was not captured (receipt='$($receipt.status)', exists=$exists, bytes=$length)." }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $currentStep = 'load-disposable-campaign'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Invoke-AgentCli 'state' @('-CommandId', "$prefix-initial")
    if ($initial.state.context.gameState -ne 'MapState' -or $initial.state.context.encounterActive -or $initial.state.context.captivity)
        { throw 'Fixture must start in a free Campaign Map state with no active Encounter.' }

    $currentStep = 'prepare-native-engaging-bandit'
    $banditFixture = Invoke-AgentCli 'harnessPrepareSafePassageFixture' @('-CommandId', "$prefix-bandit-fixture") 30
    if ($banditFixture.status -ne 'completed' -or [string]::IsNullOrWhiteSpace([string]$banditFixture.data.partyId) -or -not [bool]$banditFixture.data.hostile)
        { throw 'Native hostile BanditFaction encounter fixture was not created.' }

    $currentStep = 'approach-engaging-bandit-through-native-map-navigation'
    $approach = Invoke-AgentCli 'moveToPoint' @(
        '-X', ([double]$banditFixture.data.playerApproachPoint.x).ToString([Globalization.CultureInfo]::InvariantCulture),
        '-Y', ([double]$banditFixture.data.playerApproachPoint.y).ToString([Globalization.CultureInfo]::InvariantCulture),
        '-Surface', 'land', '-CommandId', "$prefix-native-approach") 30
    if ($approach.status -ne 'completed' -or $approach.state.party.defaultBehavior -ne 'GoToPoint' -or $approach.timeControlMode -ne 'StoppablePlay')
        { throw 'Native point navigation did not start the approach in ordinary StoppablePlay mode.' }

    $currentStep = 'wait-for-native-bandit-encounter'
    $deadline = [DateTime]::UtcNow.AddSeconds($EncounterWaitSeconds)
    $encounter = $null
    $banditMeeting = $null
    $consecutiveTimeouts = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $state = Invoke-AgentCli 'state' @('-CommandId', "$prefix-encounter-poll-$([Guid]::NewGuid().ToString('N'))") 8
            $consecutiveTimeouts = 0
        }
        catch {
            if ($_.Exception.Message -notmatch 'timed out after') { throw }
            $consecutiveTimeouts++
            if ($consecutiveTimeouts -ge 3) { throw 'Game stopped answering while waiting for its native encounter menu.' }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the native encounter menu appeared.' }
            continue
        }
        if ($state.state.context.menuId -eq 'encounter' -and [bool]$state.state.context.encounterActive -and
            $state.state.context.encounteredPartyId -eq $banditFixture.data.partyId) { $encounter = $state; break }
        if ([bool]$state.state.context.encounterActive -and $state.state.context.encounteredPartyId -eq $banditFixture.data.partyId -and $state.state.context.conversation) { $banditMeeting = $state; break }
        if ($state.state.context.captivity) { throw 'MainHero was captured before the surrender menu action was selected.' }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the encounter menu appeared.' }
        Start-Sleep -Milliseconds 300
    }
    if (-not $encounter -and -not $banditMeeting)
        { throw 'The engaging Native bandit did not open a MapEvent Encounter or its native meeting Conversation.' }

    $banditFightChoice = $null
    $banditDialogueFrame = $null
    if ($banditMeeting) {
        $currentStep = 'select-current-native-bandit-fight-dialogue-option'
        $banditDialogueFrame = Join-Path $frameRoot 'encounter-surrender-bandit-dialogue.bmp'
        Capture-EngineFrame $banditDialogueFrame 'bandit-dialogue-frame'
        $fightOption = @($banditMeeting.state.context.conversation.options | Where-Object { $_.id -eq 'bandit_start_defender_1' -and $_.clickable } | Select-Object -First 1)
        if ($fightOption.Count -ne 1) { throw "The current Native Bandit meeting did not expose a clickable Fight option. Visible=$(($banditMeeting.state.context.conversation.options | ForEach-Object id) -join ',')" }
        $banditFightChoice = Invoke-AgentCli 'dialogueSelect' @('-OptionId', 'bandit_start_defender_1', '-CommandId', "$prefix-native-bandit-fight") 15
        if ($banditFightChoice.status -ne 'completed') { throw "Native Bandit Fight dialogue choice was rejected: $($banditFightChoice.error)" }

        $currentStep = 'wait-for-native-encounter-menu-after-bandit-fight-choice'
        $fightDeadline = [DateTime]::UtcNow.AddSeconds(20)
        while ([DateTime]::UtcNow -lt $fightDeadline) {
            $encounter = Invoke-AgentCli 'state' @('-CommandId', "$prefix-fight-poll-$([Guid]::NewGuid().ToString('N'))") 8
            if ($encounter.state.context.menuId -eq 'encounter' -and [bool]$encounter.state.context.encounterActive -and $encounter.state.context.encounteredPartyId -eq $banditFixture.data.partyId) { break }
            $conversation = $encounter.state.context.conversation
            if ($conversation -and @($conversation.options | Where-Object clickable).Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$conversation.sentenceText)) {
                $continue = Invoke-AgentCli 'dialogueContinue' @('-CommandId', "$prefix-fight-response-continue") 10
                if ($continue.status -ne 'completed') { throw "Native Bandit fight response line could not continue: $($continue.error)" }
            }
            elseif ($conversation -and @($conversation.options | Where-Object clickable).Count -gt 0) { throw 'Unexpected new player choice appeared after selecting the Native Bandit Fight option.' }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited before the Encounter menu appeared.' }
            Start-Sleep -Milliseconds 150
        }
    }
    if (-not $encounter -or $encounter.state.context.menuId -ne 'encounter' -or -not [bool]$encounter.state.context.encounterActive -or $encounter.state.context.encounteredPartyId -ne $banditFixture.data.partyId)
        { throw "Native Bandit Fight did not enter its Encounter menu. LastState=$($encounter.state.context | ConvertTo-Json -Depth 6 -Compress)" }

    $currentStep = 'prepare-native-surrender-condition-in-active-encounter'
    $surrenderFixture = Invoke-AgentCli 'harnessPrepareSurrenderCondition' @('-CommandId', "$prefix-surrender-condition") 30
    if ($surrenderFixture.status -ne 'completed' -or -not [bool]$surrenderFixture.data.heroIsWounded -or [bool]$surrenderFixture.data.nativeCanPartyAttackAfter -or $surrenderFixture.data.currentMenuId -ne 'encounter')
        { throw 'Native wounded-Hero/low-morale surrender condition was not established in the active Encounter menu.' }
    $encounter = Invoke-AgentCli 'state' @('-CommandId', "$prefix-encounter-after-condition")
    $surrenderOption = @($encounter.state.availableMenuOptions | Where-Object { $_.id -eq 'surrender' -and $_.available -and $_.enabled })
    if ($surrenderOption.Count -ne 1)
        { throw "Native Encounter menu did not expose one enabled Surrender option. Condition=$($surrenderFixture.data | ConvertTo-Json -Compress) Options=$(($encounter.state.availableMenuOptions | ForEach-Object { "$($_.id):$($_.available):$($_.enabled)" }) -join ',')" }

    $currentStep = 'capture-encounter-menu-frame'
    $beforeFrame = Join-Path $frameRoot 'encounter-surrender-before.bmp'
    $afterFrame = Join-Path $frameRoot 'encounter-surrender-after.bmp'
    Capture-EngineFrame $beforeFrame 'before-surrender-frame'

    $currentStep = 'select-current-native-surrender-option'
    $beforeSurrender = Invoke-AgentCli 'harnessCaptivityDiagnostics' @('-PartyId', [string]$banditFixture.data.partyId, '-CommandId', "$prefix-before-surrender") 30
    $selection = Invoke-AgentCli 'menuSelect' @('-MenuId', 'encounter', '-OptionId', 'surrender', '-CommandId', "$prefix-native-surrender") 30
    if ($selection.status -ne 'completed') { throw "Native Encounter surrender option was rejected: $($selection.error)" }

    $currentStep = 'observe-native-player-surrender-result'
    $post = $null
    $postDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $postDeadline) {
        $post = Invoke-AgentCli 'state' @('-CommandId', "$prefix-post-surrender-$([Guid]::NewGuid().ToString('N'))") 10
        if ($post.state.context.captivity -and -not [bool]$post.state.context.encounterActive) { break }
        if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Bannerlord exited while resolving the Native surrender.' }
        Start-Sleep -Milliseconds 150
    }
    if (-not $post.state.context.captivity -or [bool]$post.state.context.encounterActive)
        { throw "Native surrender did not produce an observed Captivity state. LastState=$($post.state.context | ConvertTo-Json -Depth 6 -Compress)" }
    Capture-EngineFrame $afterFrame 'after-surrender-frame'
    $captivity = Invoke-AgentCli 'harnessCaptivityDiagnostics' @('-PartyId', [string]$banditFixture.data.partyId, '-CommandId', "$prefix-after-surrender-diagnostics") 30
    if ($captivity.status -ne 'completed') { throw 'Native captivity diagnostics were unavailable after surrender.' }
    $continueOption = @($post.state.availableMenuOptions | Where-Object { $_.id -eq 'mno_continue' -and $_.available -and $_.enabled })
    $before = $beforeSurrender.data
    $after = $captivity.data
    $result = [ordered]@{
        ProviderKind = 'Native Campaign encounter Surrender using a visible encounter option and its full Native MapEvent consequence; test-only wounded/morale setup'
        ProcessId = $start.session.processId
        BanditFixture = $banditFixture.data
        SurrenderConditionFixture = $surrenderFixture.data
        PlayerApproach = $approach
        BanditMeetingFrame = $banditDialogueFrame
        NativeBanditFightDialogueChoice = $banditFightChoice
        EncounterMenu = [ordered]@{ menuId = $encounter.state.context.menuId; encounteredPartyId = $encounter.state.context.encounteredPartyId; option = [ordered]@{ id = $surrenderOption[0].id; text = $surrenderOption[0].text } }
        Selection = $selection
        Captivity = $post.state.context.captivity
        CaptivityMenuId = $post.state.context.menuId
        CaptivityOptions = @($post.state.availableMenuOptions | Where-Object { $_.available -and $_.enabled } | ForEach-Object { [ordered]@{ id = $_.id; text = $_.text } })
        ContinueAvailable = ($continueOption.Count -eq 1)
        Before = $before
        After = $after
        BeforeCampaignDay = $encounter.campaignDay
        AfterCampaignDay = $post.campaignDay
        TimeControlModeBefore = $encounter.timeControlMode
        TimeControlModeAfter = $post.timeControlMode
        EngineFrames = @($beforeFrame, $afterFrame)
        NativeSurrenderOptionObservedAndSelected = ($surrenderOption.Count -eq 1 -and $selection.status -eq 'completed')
        CaptivityTriggeredFromNativeEncounter = ([bool]$post.state.context.captivity.isCaptive -and $after.heroIsPrisoner -and $after.captorRosterContainsMainHero)
        PartyDisabledDuringCaptivity = (-not $after.mainPartyIsActive -and -not $after.mainPartyContainsMainHero)
        NativeCaptivityWaitMenuObserved = ($post.state.context.menuId -eq 'prisoner_wait')
        ContinueOptionVisible = ($continueOption.Count -eq 1)
        FixtureHashUnchanged = $false
        ProcessStopped = $false
        Passed = $false
    }

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$prefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $result.FixtureHashUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
    $result.ProcessStopped = [bool]$stop.processStopped
    $result.Passed = ($result.NativeSurrenderOptionObservedAndSelected -and $result.CaptivityTriggeredFromNativeEncounter -and
        $result.PartyDisabledDuringCaptivity -and $result.NativeCaptivityWaitMenuObserved -and -not $result.ContinueOptionVisible -and
        $result.FixtureHashUnchanged -and $result.ProcessStopped)
    $json = $result | ConvertTo-Json -Depth 16
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) { Set-Content -LiteralPath $resultPath -Value $json -Encoding UTF8 }
    $json
    if (-not $result.Passed) { exit 1 }
}
catch {
    $failureFrame = Capture-HarnessFailureFrame -CliPath $cli -CommandPrefix $prefix -FailedStep $currentStep -FailureReason $_.Exception.ToString()
    if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Container)) {
        [ordered]@{ FailedStep = $currentStep; Exception = $_.Exception.ToString(); FailureFrame = $failureFrame; TimestampUtc = [DateTime]::UtcNow.ToString('O') } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tempPath 'EncounterSurrenderFailure.json') -Encoding UTF8
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
