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
if ($MaxDecisions -lt 1 -or $MaxDecisions -gt 100) { throw 'MaxDecisions must be between 1 and 100.' }

function Invoke-AgentCli {
    param([string]$Action, [hashtable]$Arguments = @{}, [string]$CommandId)
    $cliArguments = @($Action, '-CommandId', $CommandId, '-TimeoutSeconds', [string]$TimeoutSeconds, '-AsJson')
    foreach ($key in $Arguments.Keys) {
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

function Convert-DecisionToCli {
    param($Decision)
    if ($Decision.action -eq 'advance') { throw 'advance is a Harness-only deterministic time step and is unavailable to Agent decision providers.' }
    $allowed = @{
        state = @(); mapSettlementTargets = @(); mapPartyTargets = @(); mapPartyComposition = @('PartyId'); mapPartyBehavior = @('PartyId'); partyUpgradeOptions = @(); upgradeTroop = @('TroopId','UpgradeTargetIndex'); prisonerRecruitmentOptions = @(); recruitPrisoner = @('TroopId','ConfirmPartySizeWarning'); characterDevelopment = @(); spendSkillFocus = @('SkillId','Count'); questDetails = @('QuestId'); partyRoster = @(); pause = @(); resume = @(); move = @('SettlementId'); moveToPoint = @('X','Y','Surface'); missionInput = @('X','Y','DurationSeconds'); missionNavigateToAgent = @('AgentIndex'); missionInteract = @('AgentIndex'); missionCancelNavigation = @(); missionAimAt = @('AgentIndex');
        pursue = @('PartyId'); follow = @('PartyId'); hold = @(); menu = @(); menuSelect = @('MenuId','OptionId'); talkToSettlementHero = @('HeroId'); dialogueSelect = @('OptionId'); dialogueContinue = @();
        battlePause = @(); battleSkip = @(); battleFinish = @(); battleRetreat = @(); missionRetreat = @();
        partyTakeAll = @('LootType'); partyScreenDone = @(); inventoryTakeAll = @(); inventoryDone = @();
        rest = @('Days'); recruitOptions = @(); recruit = @('OwnerId','TroopId','VolunteerSlot');
        foodOptions = @(); tradeOptions = @(); trade = @('Direction','ItemId','Amount'); provision = @('ItemId','Amount')
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
    $observation = Invoke-AgentCli 'state' @{} "$CommandPrefix-observe-0"
    $previousActionReceipt = $null
    if ($observation.status -ne 'completed' -or -not $observation.state) { throw 'Initial game observation was not completed.' }
    for ($index = 1; $index -le $MaxDecisions; $index++) {
        $request = [ordered]@{
            schemaVersion = 1
            runId = $loopRunId
            iteration = $index
            observation = $observation
            previousActionReceipt = $previousActionReceipt
        }
        $decision = Invoke-DecisionProvider ($request | ConvertTo-Json -Depth 16 -Compress)
        $validated = Convert-DecisionToCli $decision
        $commandId = "$CommandPrefix-act-$index"
        $actionResult = Invoke-AgentCli $validated.Action $validated.Arguments $commandId
        if ($actionResult.status -notin @('completed','accepted')) { throw "Action '$($validated.Action)' returned '$($actionResult.status)': $($actionResult.error)" }
        $nextObservation = Invoke-AgentCli 'state' @{} "$CommandPrefix-observe-$index"
        if ($nextObservation.status -ne 'completed' -or -not $nextObservation.state) { throw 'Post-action observation was not completed.' }
        $trace += [pscustomobject]@{
            iteration = $index
            observationBefore = $observation
            previousActionReceipt = $previousActionReceipt
            decision = $decision
            actionReceipt = $actionResult
            observationAfter = $nextObservation
        }
        $previousActionReceipt = $actionResult
        $observation = $nextObservation
    }

    [pscustomobject]@{
        schemaVersion = 1
        runId = $loopRunId
        provider = $providerPath
        decisions = $MaxDecisions
        trace = $trace
    } | ConvertTo-Json -Depth 20
}
catch {
    [pscustomobject]@{ status = 'failed'; error = $_.Exception.Message } | ConvertTo-Json -Compress
    exit 1
}
