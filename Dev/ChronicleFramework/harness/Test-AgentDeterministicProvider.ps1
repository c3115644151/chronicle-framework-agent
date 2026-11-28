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
        # Encounter menu: str_order_attack is the original Send Troops/BattleSimulation
        # route and the only way to advance the EYC Renown objective; prefer it over leave.
        $attack = @($values | Where-Object { [string]$_ -cmatch 'str_order_attack' })
        if ($attack.Count -gt 0 -and (Test-ShouldAttack $script:CurrentObs)) { return $attack[0] }
        $safe = @($values | Where-Object { [string]$_ -match '(?i)leave|exit|back|done|finish|decline|reject|refuse|end|离开|结束|拒绝' })
        if ($safe.Count -gt 0) { return $safe[0] }
    }
    return $values[0]
}
# A lone, wounded hero loses every 1v3 bandit fight and ends up captured, which resets the whole loop.
# Only take the Send Troops route when the party outnumbers the encountered bandits.
function Test-ShouldAttack($obs) {
    $state = Get-Arg $obs 'state'
    $party = Get-Arg $state 'party'
    $members = [double](Get-Arg $party 'members')
    $hero = [double](Get-Arg $party 'heroHitPoints')
    $ctx = Get-Arg $state 'context'
    $enemyId = [string](Get-Arg $ctx 'encounteredPartyId')
    $enemyMembers = 0.0
    foreach ($p in @(Get-Arg $state 'nearbyParties')) {
        if ([string](Get-Arg $p 'id') -ceq $enemyId) { $enemyMembers = [double](Get-Arg $p 'members') }
    }
    if ($members -le 0) { return $false }
    if ($hero -lt 50 -and $enemyMembers -ge $members) { return $false }
    return ($members + 1) -ge ($enemyMembers + 2)
}

function Build-Arguments($action, $obs = $null) {
    $script:CurrentObs = $obs
    $argsObj = [ordered]@{}
    foreach ($n in @(Get-Arg $action 'arguments')) {
        $v = Choose-ArgValue $action ([string]$n)
        if ($null -ne $v) { $argsObj[[string]$n] = $v }
    }
    # move needs a SettlementId; when the catalog does not narrow it, derive a safe
    # target from the current Native nearbySettlements observation (town > village,
    # non-hostile, not under siege).
    $argNames0 = @(Get-Arg $action 'arguments' | ForEach-Object { [string]$_ })
    if (($argNames0 -ccontains 'SettlementId') -and [string]$argsObj['SettlementId'] -eq '') {
        $state = Get-Arg $obs 'state'
        $nearby = @(Get-Arg $state 'nearbySettlements')
        $safe = @($nearby | Where-Object {
            (Get-Arg $_ 'hostile') -ne $true -and (Get-Arg $_ 'underSiege') -ne $true -and
            -not [string]::IsNullOrWhiteSpace([string](Get-Arg $_ 'id'))
        })
        $towns = @($safe | Where-Object { [string](Get-Arg $_ 'type') -ceq 'town' })
        $pick = $null
        # A one-member party that crosses the map gets intercepted by every nearby bandit. While the
        # party is still small, take the closest safe settlement (villages recruit volunteers too).
        $members = [double](Get-Arg (Get-Arg (Get-Arg $obs 'state') 'party') 'members')
        if ($members -lt 6 -and $safe.Count -gt 0) {
            $near = @($safe | Sort-Object { [double](Get-Arg $_ 'distance') } | Select-Object -First 1)
            $pick = $near[0]
        } elseif ($towns.Count -gt 0) { $pick = $towns[0] } elseif ($safe.Count -gt 0) { $pick = $safe[0] }
        if ($null -ne $pick) { $argsObj['SettlementId'] = [string](Get-Arg $pick 'id') }
    }
    # pursue needs a PartyId; derive the weakest currently visible hostile bandit
    # from the current Native nearbyParties observation (lowest strength improves odds).
    if (($argNames0 -ccontains 'PartyId') -and [string]$argsObj['PartyId'] -eq '') {
        $state = Get-Arg $obs 'state'
        $parties = @(Get-Arg $state 'nearbyParties')
        $hostile = @($parties | Where-Object {
            (Get-Arg $_ 'hostile') -eq $true -and
            -not [string]::IsNullOrWhiteSpace([string](Get-Arg $_ 'id'))
        })
        if ($hostile.Count -gt 0) {
            $weakest = @($hostile | Sort-Object { [double](Get-Arg $_ 'strength') } | Select-Object -First 1)[0]
            $argsObj['PartyId'] = [string](Get-Arg $weakest 'id')
        }
    }
# StoryMode clan-name inquiry: the Native question supplies no argument values, only the suggested
    # input text. Returning an empty text is rejected as storymode-clan-name-decision-invalid.
    if (($argNames0 -ccontains 'text') -and [string]$argsObj['text'] -eq '') {
        $ctx = Get-Arg (Get-Arg $obs 'state') 'context'
        $inquiry = Get-Arg $ctx 'inquiry'
        $suggested = [string](Get-Arg $inquiry 'inputText')
        if ([string]::IsNullOrWhiteSpace($suggested)) { $suggested = [string](Get-Arg $inquiry 'defaultInputText') }
        if ([string]::IsNullOrWhiteSpace($suggested)) { $suggested = 'Chronica' }
        if ($suggested.Length -gt 64) { $suggested = $suggested.Substring(0, 64) }
        $argsObj['text'] = $suggested
    }

    # Prefer a complete legal tuple for cross-field-constrained actions (recruit).
    $tuples = Get-Arg $action 'legalTuples'
    if ($null -ne $tuples -and @($tuples).Count -gt 0) {
        $t = @($tuples)[0]
        foreach ($prop in $t.PSObject.Properties) {
            # legalTuples describe one Native offer; fields such as cost or ownerName are display
            # data, not action arguments. Sending them would be rejected as an unknown argument.
            if ($argNames0.Count -gt 0 -and ($argNames0 -cnotcontains [string]$prop.Name)) { continue }
            $pv = $prop.Value
            # Host schemas expect scalars; legalTuples may encode confirmPartySizeWarning as [0].
            if ($null -ne $pv -and @($pv).Count -eq 1 -and $pv -is [array]) { $pv = @($pv)[0] }
            $argsObj[$prop.Name] = $pv
        }
    }
    return $argsObj
}
function Get-ObserveWaitSeconds($decisionInput) {
    $ca = Get-Arg $decisionInput 'controlArguments'
    $oa = Get-Arg $ca 'observeAgain'
    $ws = Get-Arg $oa 'waitSeconds'
    $max = 10
    $min = 1
    $mx = Get-Arg $ws 'maximum'; if ($null -ne $mx) { $max = [int]$mx }
    $mn = Get-Arg $ws 'minimum'; if ($null -ne $mn) { $min = [int]$mn }
    if ($min -gt $max) { $min = $max }
    return $max
}
function Pick-Decision($decisionInput) {
    if ($env:CHRONICLE_DETERMINISTIC_TRACE) {
        $decisionInput | ConvertTo-Json -Depth 20 -Compress | Add-Content -LiteralPath $env:CHRONICLE_DETERMINISTIC_TRACE -Encoding UTF8
    }
    $actions = @(Get-Arg $decisionInput 'allowedActions')
    $controls = @(Get-Arg $decisionInput 'allowedControls')
    $obs = Get-Arg $decisionInput 'observation'
# Goal controls are published by the Host in camel case; the harness goal ids are kebab case. Keep one
# explicit mapping so the stub rationale names the same goal the Harness layer reports.
function Get-GoalControlSlug([string]$control) {
    switch ($control) {
        'supportedMapArrivalGoal' { return 'supported-map-arrival' }
        'supportedVillageToolsQuestGoal' { return 'supported-village-tools-quest' }
        'supportedBattleSimulationGoal' { return 'supported-battle-simulation' }
        'supportedBattleAndCaptivityGoal' { return 'supported-battle-and-captivity' }
        'supportedEstablishYourClanGoal' { return 'supported-establish-your-clan' }
        'supportedCaptivityRecoveryGoal' { return 'supported-captivity-recovery' }
        'supportedEstablishClanGoldSaleGoal' { return 'supported-establish-clan-gold-sale' }
        'supportedTownTradeGoal' { return 'supported-town-trade' }
        'supportedTournamentGoal' { return 'supported-tournament' }
        default { return 'unsupported-goal' }
    }
}

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
        return @{ control = $chosen; rationale = ('deterministic: goal control ' + (Get-GoalControlSlug ([string]$chosen))) }
    }
    # Bounded observe-again control: wait 1-10 seconds, Host-side only.
    if ($controls -ccontains 'observeAgain' -and ($actions.Count -eq 0 -or $actions.Count -eq 1)) {
        return @{ control = 'observeAgain'; waitSeconds = (Get-ObserveWaitSeconds $decisionInput); rationale = 'deterministic: wait for fresh Native observation' }
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
            if ($c -ceq 'observeAgain') { return @{ control = 'observeAgain'; waitSeconds = (Get-ObserveWaitSeconds $decisionInput); rationale = 'deterministic: wait for fresh Native observation' } }
            if ($c) { return @{ control = $c; rationale = 'deterministic: sole control' } }
        }
        return @{ action = $name; arguments = Build-Arguments $a $obs; rationale = 'deterministic: sole current action' }
    }
    # Multiple actions: prefer a state-advancing Native action by fixed priority.
    $priority = @('recruit','recruitOptions','tradeOptions','trade','tradeConfirm','partyTakeAll','inventoryTakeAll','partyScreenDone','inventoryDone','mapSettlementTargets','menuSelect','move','mapPartyTargets','pursue','dialogueSelect','dialogueContinue','battleSkip','battleFinish','incidentSelect','prisonerRecruitmentOptions','partyLootTransferOne')
    foreach ($want in $priority) {
        $a = @($actions | Where-Object { (Get-Arg $_ 'action') -ceq $want } | Select-Object -First 1)
        if ($a.Count -eq 1) { return @{ action = $want; arguments = Build-Arguments $a[0] $obs; rationale = 'deterministic: priority action' } }
    }
    $a0 = $actions[0]
    return @{ action = [string](Get-Arg $a0 'action'); arguments = Build-Arguments $a0 $obs; rationale = 'deterministic: fallback first action' }
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
    T 'legal-tuple-complete' '{"allowedActions":[{"action":"recruit","arguments":["ownerId","troopId","slot","confirmPartySizeWarning"],"argumentValues":{"ownerId":["CharacterObject_1789","CharacterObject_1790"],"troopId":["imperial_recruit"],"slot":[0,1],"confirmPartySizeWarning":[false]},"legalTuples":[{"ownerId":"CharacterObject_1790","troopId":"imperial_recruit","slot":0,"cost":20,"ownerName":"x","confirmPartySizeWarning":false}]}],"allowedControls":[],"observation":{}}' {
        param($d)
        $names = @($d.arguments.Keys)
        $extra = @($names | Where-Object { @('ownerId','troopId','slot','confirmPartySizeWarning') -cnotcontains $_ })
        $d.action -ceq 'recruit' -and $d.arguments.ownerId -ceq 'CharacterObject_1790' -and [int]$d.arguments.slot -eq 0 -and $extra.Count -eq 0
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
