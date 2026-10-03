[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DecisionProviderPath,
    [int]$MaxDecisions = 1,
    [int]$TimeoutSeconds = 180,
    [string]$CommandPrefix = 'loop'
)

$ErrorActionPreference = 'Stop'
$cliPath = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$providerPath = (Resolve-Path -LiteralPath $DecisionProviderPath).Path
if ($MaxDecisions -lt 1 -or $MaxDecisions -gt 400) { throw 'MaxDecisions must be between 1 and 400.' }

function Invoke-AgentCli {
    param([string]$Action, [hashtable]$Arguments = @{}, [string]$CommandId)
    $cliArguments = @($Action, '-CommandId', $CommandId, '-TimeoutSeconds', [string]$TimeoutSeconds, '-AsJson')
    foreach ($key in $Arguments.Keys) {
        if ($key -eq 'ConfirmPartySizeWarning') {
            if ([bool]$Arguments[$key]) { $cliArguments += '-ConfirmPartySizeWarning' }
            continue
        }
        $cliArguments += "-$key"
        $cliArguments += [string]$Arguments[$key]
    }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath @cliArguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Invoke-DecisionProvider {
    param([string]$RequestJson)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$providerPath`""
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Could not start the decision provider.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.WriteLine($RequestJson)
    $process.StandardInput.Close()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        throw "Decision provider timed out after $TimeoutSeconds seconds."
    }
    $stdout = $stdoutTask.Result.Trim()
    $stderr = $stderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) { throw "Decision provider exited $($process.ExitCode): $stderr" }
    try { return $stdout | ConvertFrom-Json }
    catch { throw "Decision provider returned invalid JSON: $stdout $stderr" }
}

function ConvertTo-AsciiJson([string]$Json) {
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Json.ToCharArray()) {
        if ([int]$character -gt 127) { [void]$builder.AppendFormat('\u{0:X4}', [int]$character) }
        else { [void]$builder.Append($character) }
    }
    return $builder.ToString()
}

function Convert-DecisionToCli {
    param($Decision)
    if ($Decision.action -eq 'advance') { throw 'advance is a Harness-only deterministic time step and is unavailable to Agent decision providers.' }
    $allowed = @{
        state = @(); closeEscapeMenu = @(); respondInquiry = @('InquiryToken','InquiryChoice'); mapSettlementTargets = @(); mapNotifications = @(); quickInformation = @(); sceneNotification = @(); mapPartyTargets = @(); mapPartyComposition = @('PartyId'); mapPartyBehavior = @('PartyId'); partyUpgradeOptions = @(); upgradeTroop = @('TroopId','UpgradeTargetIndex'); prisonerRecruitmentOptions = @(); recruitPrisoner = @('TroopId','ConfirmPartySizeWarning'); characterDevelopment = @(); spendSkillFocus = @('SkillId','Count'); questDetails = @('QuestId'); partyRoster = @(); partyRoles = @(); setPartyRole = @('RoleId','HeroId'); unassignPartyRole = @('RoleId'); inventoryOpen = @(); heroEquipmentOptions = @(); equipHeroItem = @('ItemViewModelId','EquipmentIndex'); unequipHeroItem = @('EquipmentIndex'); inventoryConfirm = @(); inventoryCancel = @(); inventoryCancelChanges = @(); pause = @(); resume = @(); fastForward = @(); move = @('SettlementId'); moveToPoint = @('X','Y','Surface'); missionInput = @('X','Y','DurationSeconds'); missionNavigateToAgent = @('AgentIndex','DurationSeconds'); missionLeave = @(); missionInteract = @('AgentIndex'); missionCancelNavigation = @(); missionAimAt = @('AgentIndex');
        pursue = @('PartyId'); follow = @('PartyId'); hold = @(); menu = @(); menuSelect = @('MenuId','OptionId'); talkToSettlementHero = @('HeroId'); visitSettlementHero = @('HeroId'); dialogueSelect = @('OptionId'); dialogueContinue = @();
        battlePause = @(); battleSkip = @(); battleFinish = @(); battleRetreat = @(); missionRetreat = @();
        partyTakeAll = @('LootType'); partyScreenDone = @(); inventoryTakeAll = @(); inventoryDone = @();
        rest = @('Days'); recruitOptions = @(); recruit = @('OwnerId','TroopId','VolunteerSlot','ConfirmPartySizeWarning');
        foodOptions = @(); tradeOptions = @(); tradeRumors = @('ItemViewModelId','InventorySide'); trade = @('Direction','ItemViewModelId','InventorySide','Amount'); provision = @('ItemViewModelId','Amount'); tradeConfirm = @(); tradeCancel = @(); tradeCancelChanges = @(); barterOptions = @(); barterEdit = @('BarterCandidateId','BarterOperation','Amount'); barterReset = @(); barterAutoBalance = @(); barterOffer = @(); barterCancel = @()
    }
    if (-not $Decision -or $Decision.action -notin $allowed.Keys) { throw 'Decision action is not in the Agent CLI allowlist.' }
    $arguments = @{}
    if ($Decision.arguments) {
        foreach ($property in $Decision.arguments.PSObject.Properties) {
            if ($property.Name -notin $allowed[[string]$Decision.action]) { throw "Unexpected argument '$($property.Name)' for action '$($Decision.action)'." }
            $arguments[$property.Name] = $property.Value
        }
    }
    foreach ($required in $allowed[[string]$Decision.action]) {
        if (-not $arguments.ContainsKey($required)) { throw "Missing '$required' for action '$($Decision.action)'." }
    }
    return [pscustomobject]@{ Action = [string]$Decision.action; Arguments = $arguments }
}

try {
    $trace = @()
    $loopRunId = [Guid]::NewGuid().ToString('N')
    $observation = $null
    $previousActionReceipt = $null
    $observation = Invoke-AgentCli 'state' @{} "$CommandPrefix-observe-0"
    $previousActionReceipt = $null
    $termination = [ordered]@{ reason = 'decision-budget-exhausted'; providerReason = $null; completedByProvider = $false }
    if ($observation.status -ne 'completed' -or -not $observation.state) { throw 'Initial game observation was not completed.' }
    for ($index = 1; $index -le $MaxDecisions; $index++) {
        $request = [ordered]@{
            schemaVersion = 1
            runId = $loopRunId
            iteration = $index
            observation = $observation
            previousActionReceipt = $previousActionReceipt
        }
        $requestJson = ConvertTo-AsciiJson ($request | ConvertTo-Json -Depth 16 -Compress)
        $decision = Invoke-DecisionProvider $requestJson
        if ($decision -and $decision.done -eq $true) {
            $doneReason = [string]$decision.reason
            if ([string]::IsNullOrWhiteSpace($doneReason)) { throw 'A provider stop decision must include a non-empty reason.' }
            $trace += [pscustomobject]@{
                iteration = $index
                observationBefore = $observation
                previousActionReceipt = $previousActionReceipt
                decision = $decision
                actionReceipt = $null
                observationAfter = $observation
                actionExecuted = $false
            }
            $termination = [ordered]@{ reason = 'provider-stop'; providerReason = $doneReason; completedByProvider = $true }
            break
        }
        $validated = Convert-DecisionToCli $decision
        $commandId = "$CommandPrefix-act-$index"
        $actionResult = Invoke-AgentCli $validated.Action $validated.Arguments $commandId
        if ($actionResult.status -notin @('completed','accepted')) {
            $trace += [pscustomobject]@{
                iteration = $index
                observationBefore = $observation
                previousActionReceipt = $previousActionReceipt
                decision = $decision
                actionReceipt = $actionResult
                observationAfter = $null
                actionAttempted = $true
                actionExecuted = $false
            }
            throw "Action '$($validated.Action)' returned '$($actionResult.status)': $($actionResult.error)"
        }
        $nextObservation = Invoke-AgentCli 'state' @{} "$CommandPrefix-observe-$index"
        if ($nextObservation.status -ne 'completed' -or -not $nextObservation.state) { throw 'Post-action observation was not completed.' }
        $trace += [pscustomobject]@{
            iteration = $index
            observationBefore = $observation
            previousActionReceipt = $previousActionReceipt
            decision = $decision
            actionReceipt = $actionResult
            observationAfter = $nextObservation
            actionAttempted = $true
            actionExecuted = $true
        }
        $previousActionReceipt = $actionResult
        $observation = $nextObservation
    }

    [pscustomobject]@{
        schemaVersion = 1
        runId = $loopRunId
        provider = $providerPath
        decisions = $trace.Count
        actionsExecuted = @($trace | Where-Object { $_.actionExecuted }).Count
        termination = $termination
        trace = $trace
    } | ConvertTo-Json -Depth 20
}
catch {
    [pscustomobject]@{
        status = 'failed'
        runId = $loopRunId
        error = $_.Exception.Message
        lastObservation = $observation
        trace = @($trace)
    } | ConvertTo-Json -Depth 20 -Compress
    exit 1
}
