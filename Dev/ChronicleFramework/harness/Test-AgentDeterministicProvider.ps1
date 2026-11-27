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
function First-ArgValue($action, [string]$name) {
    $av = Get-Arg $action 'argumentValues'
    $v = Get-Arg $av $name
    if ($null -ne $v -and @($v).Count -gt 0) { return @($v)[0] }
    return $null
}
function Build-Arguments($action) {
    $argsObj = [ordered]@{}
    foreach ($n in @(Get-Arg $action 'arguments')) {
        $v = First-ArgValue $action ([string]$n)
        if ($null -ne $v) { $argsObj[[string]$n] = $v }
    }
    # Prefer a complete legal tuple for cross-field-constrained actions (recruit).
    $tuples = Get-Arg $action 'legalTuples'
    if ($null -ne $tuples -and @($tuples).Count -gt 0) {
        $t = @($tuples)[0]
        foreach ($p in $t.PSObject.Properties) { $argsObj[$p.Name] = $p.Value }
    }
    return $argsObj
}
function Pick-Decision($decisionInput) {
    $actions = @(Get-Arg $decisionInput 'allowedActions')
    $controls = @(Get-Arg $decisionInput 'allowedControls')
    $obs = Get-Arg $decisionInput 'observation'
    # Goal classification phase: no actions, supported controls listed.
    if ($actions.Count -eq 0 -and $controls.Count -gt 0) {
        return @{ goalClassification = 'supported-establish-your-clan' }
    }
    # Objective planner: choose the first unmet objective from the current Journal snapshot.
    $hasPlanner = @($actions | Where-Object { (Get-Arg $_ 'action') -ceq 'selectEstablishYourClanObjective' }).Count -gt 0
    if ($hasPlanner) {
        $snap = Get-Arg $obs 'objectiveSnapshot'
        $pick = $null
        foreach ($o in @('gold','partySize','renown','companions')) {
            $node = Get-Arg $snap $o
            if ($null -ne $node -and (Get-Arg $node 'met') -ne $true) { $pick = $o; break }
        }
        if (-not $pick) { $pick = 'gold' }
        return @{ action = 'selectEstablishYourClanObjective'; arguments = @{ ObjectiveId = $pick }; rationale = 'deterministic: first unmet EYC objective' }
    }
    if ($actions.Count -eq 0) { return @{ done = $true; reason = 'deterministic: no current action or control' } }
    if ($actions.Count -eq 1) {
        $a = $actions[0]
        $name = [string](Get-Arg $a 'action')
        if (-not $name) {
            $c = [string](Get-Arg $a 'control')
            if ($c -ceq 'observeAgain') { return @{ observeAgain = $true; waitSeconds = 10 } }
            if ($c) { return @{ control = $c } }
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
    T 'goal-classification' '{"allowedActions":[],"allowedControls":["supportedEstablishYourClanGoal","unsupportedGoal"],"observation":{}}' {
        param($d) $d.goalClassification -ceq 'supported-establish-your-clan'
    }
    T 'objective-planner-first-unmet' '{"allowedActions":[{"action":"selectEstablishYourClanObjective","arguments":["ObjectiveId"],"argumentValues":{"ObjectiveId":["gold","partySize","renown","companions"]}}],"allowedControls":[],"observation":{"objectiveSnapshot":{"gold":{"met":true},"partySize":{"met":false},"renown":{"met":false},"companions":{"met":true}}}}' {
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
                $decision = Pick-Decision $input
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
