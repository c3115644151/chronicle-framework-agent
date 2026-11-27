#Requires -Version 7.0
[CmdletBinding()]
param([int]$Port = 0, [string]$ReadyFile = '', [switch]$SelfTest)

# Deterministic, zero-credential OpenAI-compatible provider for the real Agent Host.
# It drives the real Host->Native loop with rule-based decisions (no LLM, no network egress).
$ErrorActionPreference = 'Stop'
if (-not $SelfTest -and $Port -lt 1) { throw 'A positive -Port is required unless -SelfTest is set.' }
$modelId = 'deterministic-eyc-provider'
function Get-Arg($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}
function Arg-Values($action, [string]$name) {
    $av = Get-Arg $action 'argumentValues'
    $v = Get-Arg $av $name
    if ($null -eq $v) { return @() }
    return @($v)
}
function Choose-ArgValue($action, [string]$name) {
    $values = @(Arg-Values $action $name)
    if ($values.Count -eq 0) { return $null }
    # Menu/choice values: prefer a safe exit/leave/back/done option over enter/start.
    if ($name -match 'OptionId|Choice|choice') {
        $safe = @($values | Where-Object { [string]$_ -match '(?i)leave|exit|back|done|finish|decline|reject' })
        if ($safe.Count -gt 0) { return $safe[0] }
    }
    return $values[0]
}
function Build-Arguments($action) {
    $argsObj = [ordered]@{}
    foreach ($n in @(Get-Arg $action 'arguments')) {
        $v = Choose-ArgValue $action ([string]$n)
        if ($null -ne $v) { $argsObj[[string]$n] = $v }
    }
    # Prefer a complete legal tuple for cross-field-constrained actions (recruit).
    $tuples = Get-Arg $action 'legalTuples'
    if ($null -ne $tuples -and @($tuples).Count -gt 0) {
        $t = @($tuples)[0]
        foreach ($prop in $t.PSObject.Properties) { $argsObj[$prop.Name] = $prop.Value }
    }
    return $argsObj
}
function Pick-Decision($decisionInput) {
    if ($env:CHRONICLE_DETERMINISTIC_TRACE) {
        $decisionInput | ConvertTo-Json -Depth 20 -Compress | Add-Content -LiteralPath $env:CHRONICLE_DETERMINISTIC_TRACE -Encoding UTF8
    }
    $actions = @(Get-Arg $decisionInput 'allowedActions')
    $controls = @(Get-Arg $decisionInput 'allowedControls')
    $obs = Get-Arg $decisionInput 'observation'
    $goalNames = @('supportedMapArrivalGoal','supportedVillageToolsQuestGoal','supportedBattleSimulationGoal','supportedBattleAndCaptivityGoal','supportedEstablishYourClanGoal','supportedCaptivityRecoveryGoal','supportedEstablishClanGoldSaleGoal','supportedTownTradeGoal','supportedTournamentGoal','unsupportedGoal')
    $listedGoals = @($controls | Where-Object { $goalNames -ccontains [string]$_ })
    # Classification phase: goal controls are listed and the Host asks for scope classification.
    if ($listedGoals.Count -gt 0) {
        # Choose a goal control that is actually listed in this phase. Full campaign
        # classification lists supportedEstablishYourClanGoal; safe-settlement refresh
        # only lists supportedMapArrivalGoal/unsupportedGoal.
        $chosen = $null
        if ($listedGoals -ccontains 'supportedEstablishYourClanGoal') { $chosen = 'supportedEstablishYourClanGoal' }
        elseif ($listedGoals -ccontains 'supportedMapArrivalGoal') { $chosen = 'supportedMapArrivalGoal' }
        else { $chosen = [string]$listedGoals[0] }
        return @{ control = $chosen; rationale = 'deterministic: first listed supported goal control' }
    }
    # Bounded observe-again control: wait 1-10 seconds, Host-side only.
    if ($controls -ccontains 'observeAgain' -and ($actions.Count -eq 0 -or $actions.Count -eq 1)) {
        return @{ control = 'observeAgain'; waitSeconds = 5; rationale = 'deterministic: wait for fresh Native observation' }
    }
    # Objective planner: choose the first unmet objective from the current Journal snapshot.
    $hasPlanner = @($actions | Where-Object { (Get-Arg $_ 'action') -ceq 'selectEstablishYourClanObjective' }).Count -gt 0
    if ($hasPlanner) {
        $planner = @($actions | Where-Object { (Get-Arg $_ 'action') -ceq 'selectEstablishYourClanObjective' } | Select-Object -First 1)[0]
        # argumentValues may be narrowed by the Host to selectable goals, or still list all four.
        $values = @(Arg-Values $planner 'ObjectiveId')
        $snap = Get-Arg (Get-Arg $obs 'state') 'objectiveSnapshot'
        $pick = $null
        # Prefer the first listed value whose current Journal objective is not yet met.
        foreach ($v in $values) {
            $node = Get-Arg $snap ([string]$v)
            if ($null -ne $node -and (Get-Arg $node 'met') -ne $true) { $pick = [string]$v; break }
        }
        # Fallback: first listed value, or a snapshot-derived unmet objective.
        if (-not $pick -and $values.Count -gt 0) { $pick = [string]$values[0] }
        if (-not $pick) {
            foreach ($o in @('gold','partySize','renown','companions')) {
                $node = Get-Arg $snap $o
                if ($null -ne $node -and (Get-Arg $node 'met') -ne $true) { $pick = $o; break }
            }
        }
        if (-not $pick) { $pick = 'partySize' }
        return @{ action = 'selectEstablishYourClanObjective'; arguments = @{ ObjectiveId = $pick }; rationale = 'deterministic: first currently unmet selectable EYC objective' }
    }
    if ($actions.Count -eq 0) {
        if ($controls -ccontains 'done') { return @{ control = 'done'; rationale = 'deterministic: no further safe action' } }
        return @{ control = 'done'; rationale = 'deterministic: no current action or control' }
    }
    if ($actions.Count -eq 1) {
        $a = $actions[0]
        $name = [string](Get-Arg $a 'action')
        if (-not $name) {
            $c = [string](Get-Arg $a 'control')
            if ($c -ceq 'observeAgain') { return @{ control = 'observeAgain'; waitSeconds = 5; rationale = 'deterministic: wait for fresh Native observation' } }
            if ($c) { return @{ control = $c; rationale = 'deterministic: sole control' } }
        }
        return @{ action = $name; arguments = Build-Arguments $a; rationale = 'deterministic: sole current action' }
    }
    # Multiple actions: prefer a state-advancing Native action by fixed priority.
    $priority = @('recruitOptions','recruit','tradeOptions','trade','tradeConfirm','partyTakeAll','inventoryTakeAll','partyScreenDone','inventoryDone','mapSettlementTargets','menuSelect','move','mapPartyTargets','pursue','dialogueSelect','dialogueContinue','battleSkip','battleFinish','incidentSelect')
    foreach ($want in $priority) {
        $a = @($actions | Where-Object { (Get-Arg $_ 'action') -ceq $want } | Select-Object -First 1)
        if ($a.Count -eq 1) { return @{ action = $want; arguments = Build-Arguments $a[0]; rationale = 'deterministic: priority action' } }
    }
    $a0 = $actions[0]
    return @{ action = [string](Get-Arg $a0 'action'); arguments = Build-Arguments $a0; rationale = 'deterministic: fallback first action' }
}

if ($SelfTest) {
    function T([string]$name, [string]$json, [scriptblock]$assert) {
        $payload = $json | ConvertFrom-Json
        $d = Pick-Decision $payload
        if (-not (& $assert $d)) { throw "deterministic-provider-self-test-failed: $name -> $($d | ConvertTo-Json -Compress -Depth 8)" }
        "PASS $name"
    }
    T 'goal-classification' '{"allowedActions":[],"allowedControls":["supportedEstablishYourClanGoal","unsupportedGoal"],"goalScopeClassificationRequired":true,"observation":{}}' {
        param($d) $d.control -ceq 'supportedEstablishYourClanGoal'
    }
    T 'objective-planner-skips-met-goal' '{"allowedActions":[{"action":"selectEstablishYourClanObjective","arguments":["ObjectiveId"],"argumentValues":{"ObjectiveId":["gold","partySize","renown","companions"]}}],"allowedControls":[],"observation":{"state":{"objectiveSnapshot":{"gold":{"met":true},"partySize":{"met":false},"renown":{"met":false},"companions":{"met":true}}}}}' {
        param($d) $d.action -ceq 'selectEstablishYourClanObjective' -and $d.arguments.ObjectiveId -ceq 'partySize'
    }
    T 'sole-action' '{"allowedActions":[{"action":"mapSettlementTargets","arguments":[],"argumentValues":{}}],"allowedControls":[],"observation":{}}' {
        param($d) $d.action -ceq 'mapSettlementTargets'
    }
    T 'priority-over-first' '{"allowedActions":[{"action":"move","arguments":[],"argumentValues":{}},{"action":"recruitOptions","arguments":[],"argumentValues":{}}],"allowedControls":[],"observation":{}}' {
        param($d) $d.action -ceq 'recruitOptions'
    }
    T 'legal-tuple-complete' '{"allowedActions":[{"action":"recruit","arguments":["ownerId","troopId","slot","confirmPartySizeWarning"],"argumentValues":{"ownerId":["CharacterObject_1789","CharacterObject_1790"],"troopId":["imperial_recruit"],"slot":[0,1],"confirmPartySizeWarning":[false]},"legalTuples":[{"ownerId":"CharacterObject_1790","troopId":"imperial_recruit","slot":0,"confirmPartySizeWarning":false}]}],"allowedControls":[],"observation":{}}' {
        param($d) $d.action -ceq 'recruit' -and $d.arguments.ownerId -ceq 'CharacterObject_1790' -and [int]$d.arguments.slot -eq 0
    }
    'DETERMINISTIC-PROVIDER-SELF-TEST: ALL PASS'
    exit 0
}
$listener = [System.Net.HttpListener]::new()
$null = $listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
if ($ReadyFile) { [IO.File]::WriteAllText($ReadyFile, 'ready') }
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        try {
            $path = $ctx.Request.Url.AbsolutePath
            if ($path -ceq '/v1/models' -or $path -ceq '/models') {
                $body = @{ object='list'; data=@(@{ id=$modelId; object='model' }) } | ConvertTo-Json -Depth 6 -Compress
            }
            elseif ($path -ceq '/v1/chat/completions' -or $path -ceq '/chat/completions') {
                $reader = New-Object IO.StreamReader($ctx.Request.InputStream, $ctx.Request.ContentEncoding)
                $reqJson = $reader.ReadToEnd(); $reader.Dispose()
                $api = $reqJson | ConvertFrom-Json
                $userMsg = @($api.messages | Where-Object { (Get-Arg $_ 'role') -ceq 'user' } | Select-Object -First 1)
                $input = $null
                if ($userMsg.Count -eq 1) { $decisionInput = [string](Get-Arg $userMsg[0] 'content') | ConvertFrom-Json } else { $decisionInput = $null }
                $decision = Pick-Decision $decisionInput
                $content = $decision | ConvertTo-Json -Depth 10 -Compress
                $body = @{
                    id='chatcmpl-deterministic'; object='chat.completion'; model=$modelId
                    choices=@([ordered]@{ index=0; message=[ordered]@{ role='assistant'; content=$content }; finish_reason='stop' })
                    usage=[ordered]@{ prompt_tokens=1; completion_tokens=1; total_tokens=2 }
                } | ConvertTo-Json -Depth 10 -Compress
            }
            else { $ctx.Response.StatusCode = 404; $body = '{}' }
            $bytes = [Text.Encoding]::UTF8.GetBytes($body)
            $ctx.Response.ContentType = 'application/json; charset=utf-8'
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        finally { $ctx.Response.Close() }
    }
}
finally { if ($listener.IsListening) { $listener.Stop() }; $listener.Close() }
