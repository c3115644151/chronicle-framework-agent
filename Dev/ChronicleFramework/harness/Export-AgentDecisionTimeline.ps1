#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunDirectory,
    [string]$OutputPath = ''
)

# Export the model decision process of one Harness run into a self-contained,
# dark-themed timeline HTML. No server, no external assets; open the file directly.
$ErrorActionPreference = 'Stop'
$run = [IO.Path]::GetFullPath($RunDirectory)
if (-not (Test-Path -LiteralPath $run -PathType Container)) { throw "Run directory not found: $run" }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $run 'DecisionTimeline.html' }
$progressPath = Join-Path $run 'Temp\AgentHostProgress.jsonl'
if (-not (Test-Path -LiteralPath $progressPath -PathType Leaf)) { throw "AgentHostProgress.jsonl not found: $progressPath" }

function Get-Field($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}
function First-NonNull { foreach ($v in $args) { if ($null -ne $v -and "$v" -ne '') { return $v } }; return $null }

function Get-ObsSummary($obs) {
    $state = Get-Field $obs 'state'
    $ctx = Get-Field $state 'context'
    $econ = Get-Field $state 'economy'
    $party = Get-Field $state 'party'
    $loc = Get-Field $state 'location'
    return [ordered]@{
        campaignDay = First-NonNull (Get-Field $obs 'campaignDay') (Get-Field $state 'campaignDay')
        gameState   = First-NonNull (Get-Field $obs 'gameState') (Get-Field $ctx 'gameState')
        menuId      = First-NonNull (Get-Field $obs 'menuId') (Get-Field $ctx 'menuId')
        gold        = First-NonNull (Get-Field $obs 'gold') (Get-Field $econ 'gold')
        renown      = First-NonNull (Get-Field $obs 'renown') (Get-Field $state 'renown')
        members     = First-NonNull (Get-Field $obs 'partyMembers') (Get-Field $party 'members')
        healthy     = First-NonNull (Get-Field $obs 'partyHealthy') (Get-Field $party 'healthy')
        wounded     = First-NonNull (Get-Field $obs 'partyWounded') (Get-Field $party 'wounded')
        food        = First-NonNull (Get-Field $obs 'partyFood') (Get-Field $party 'food')
        location    = First-NonNull (Get-Field $obs 'currentSettlementId') (Get-Field $loc 'currentSettlementId')
        encounter   = First-NonNull (Get-Field $obs 'encounterActive') (Get-Field $ctx 'encounterActive')
    }
}

$items = [System.Collections.Generic.List[object]]::new()
$n = 0
foreach ($line in [IO.File]::ReadAllLines($progressPath, [Text.Encoding]::UTF8)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $rec = $line | ConvertFrom-Json } catch { continue }
    $event = [string](Get-Field $rec 'event')
    if ($event -eq 'provider-decision') {
        $n++
        $decision = Get-Field $rec 'decision'
        $action = $null; $arguments = $null; $control = $null; $classification = $null
        if ($null -ne $decision) {
            $action = Get-Field $decision 'action'
            $arguments = Get-Field $decision 'arguments'
            $control = Get-Field $decision 'control'
            $classification = Get-Field $decision 'goalClassification'
            if ($null -eq $action -and $null -ne (Get-Field $decision 'stop')) { $control = 'stop' }
            if ($null -eq $action -and $null -ne (Get-Field $decision 'observeAgain')) { $control = 'observeAgain' }
        }
        $obs = Get-Field $rec 'observation'
        $items.Add([ordered]@{
            n = $n
            kind = 'decision'
            utc = [string](Get-Field $rec 'utc')
            scope = [string](Get-Field $rec 'scope')
            action = if ($action) { [string]$action } else { $null }
            control = if ($control) { [string]$control } else { $null }
            classification = if ($classification) { [string]$classification } else { $null }
            arguments = $arguments
            feedbackKind = [string](Get-Field $rec 'decisionFeedbackKind')
            feedbackCode = [string](Get-Field $rec 'decisionFeedbackCode')
            promptTokens = Get-Field $rec 'promptTokens'
            completionTokens = Get-Field $rec 'completionTokens'
            modelId = [string](Get-Field $rec 'modelId')
            obs = Get-ObsSummary $obs
            obsFull = $obs
            allowed = Get-Field $rec 'allowedActions'
        })
    }
    elseif ($event -eq 'objective-subflow-result') {
        $n++
        $items.Add([ordered]@{
            n = $n
            kind = 'subflow'
            utc = [string](Get-Field $rec 'utc')
            objectiveId = [string](Get-Field $rec 'objectiveId')
            status = [string](Get-Field $rec 'status')
            termination = [string](Get-Field $rec 'termination')
            failureCode = [string](Get-Field $rec 'failureCode')
            actionsExecuted = Get-Field $rec 'actionsExecuted'
            decisions = Get-Field $rec 'decisions'
            promptTokens = Get-Field $rec 'promptTokens'
            completionTokens = Get-Field $rec 'completionTokens'
        })
    }
}

# Verdict from run.log
$verdict = [ordered]@{ passed = $null; failure = ''; fixtureUnchanged = $null; visualEvidence = $null }
$runLog = Join-Path $run 'run.log'
if (Test-Path -LiteralPath $runLog -PathType Leaf) {
    $rl = [IO.File]::ReadAllText($runLog, [Text.Encoding]::UTF8)
    if ($rl -match '"Passed"\s*:\s*(true|false)') { $verdict.passed = ($Matches[1] -eq 'true') }
    if ($rl -match '"Failure"\s*:\s*"((?:[^"\\]|\\.)*)"') { $verdict.failure = $Matches[1] }
    if ($rl -match '"FixtureUnchanged"\s*:\s*(true|false)') { $verdict.fixtureUnchanged = ($Matches[1] -eq 'true') }
    if ($rl -match '"VisualEvidencePassed"\s*:\s*(true|false)') { $verdict.visualEvidence = ($Matches[1] -eq 'true') }
}

$dataJson = $items | ConvertTo-Json -Depth 40 -Compress
$verdictJson = $verdict | ConvertTo-Json -Depth 6 -Compress
# Protect the inline script tag from any '</' sequence inside serialized observations.
$dataJson = $dataJson.Replace('</', '<\\/')
$verdictJson = $verdictJson.Replace('</', '<\\/')
$runName = Split-Path -Leaf $run
$generated = (Get-Date).ToString('o')

$template = @'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Chronicle 决策过程 · {{RUN}}</title>
<style>
  :root{
    --bg:#0d1117; --panel:#161b22; --panel2:#1c2230; --border:#30363d;
    --text:#e6edf3; --muted:#8b949e; --action:#58a6ff; --classify:#bc8cff;
    --ok:#3fb950; --fail:#f85149; --wait:#d29922; --sub:#7d8590;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--text);font:14px/1.5 -apple-system,"Segoe UI",Roboto,sans-serif}
  header{padding:20px 24px;border-bottom:1px solid var(--border);background:var(--panel)}
  h1{font-size:19px;margin:0 0 4px}
  .sub{color:var(--muted);font-size:12px}
  .summary{display:flex;flex-wrap:wrap;gap:10px;margin-top:14px}
  .stat{background:var(--panel2);border:1px solid var(--border);border-radius:8px;padding:8px 12px;min-width:96px}
  .stat b{display:block;font-size:20px;line-height:1.2}
  .stat span{color:var(--muted);font-size:11px}
  .verdict{padding:6px 10px;border-radius:6px;font-weight:600}
  .v-pass{background:rgba(63,185,80,.15);color:var(--ok);border:1px solid var(--ok)}
  .v-fail{background:rgba(248,81,73,.15);color:var(--fail);border:1px solid var(--fail)}
  .v-na{background:rgba(139,148,158,.15);color:var(--muted);border:1px solid var(--border)}
  .failure{margin-top:10px;color:var(--fail);font:12px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace;white-space:pre-wrap;word-break:break-word}
  .bar{position:sticky;top:0;z-index:5;display:flex;flex-wrap:wrap;gap:10px;align-items:center;padding:10px 24px;background:rgba(13,17,23,.95);border-bottom:1px solid var(--border);backdrop-filter:blur(6px)}
  .bar input,.bar select{background:var(--panel2);color:var(--text);border:1px solid var(--border);border-radius:6px;padding:6px 9px;font-size:13px}
  .bar input[type=search]{min-width:220px}
  .bar label{color:var(--muted);font-size:12px;display:flex;gap:5px;align-items:center}
  .bar a{color:var(--action);text-decoration:none;font-size:12px}
  main{max-width:1040px;margin:0 auto;padding:18px 24px 80px}
  .hint{color:var(--muted);font-size:12px;margin-bottom:14px}
  .node{border-left:2px solid var(--border);margin-left:12px;padding:0 0 14px 18px;position:relative}
  .card{background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:12px 14px;cursor:pointer;transition:border-color .12s,background .12s}
  .card:hover,.card:focus-visible{border-color:var(--action);background:var(--panel2);outline:none}
  .row{display:flex;flex-wrap:wrap;gap:10px;align-items:center}
  .num{color:var(--muted);font:12px ui-monospace,Consolas,monospace;min-width:38px}
  .time{color:var(--muted);font:11px ui-monospace,Consolas,monospace}
  .badge{font-size:11px;padding:2px 8px;border-radius:999px;border:1px solid var(--border);color:var(--muted);white-space:nowrap}
  .b-action{color:var(--action);border-color:var(--action)}
  .b-classify{color:var(--classify);border-color:var(--classify)}
  .b-control{color:var(--wait);border-color:var(--wait)}
  .b-ok{color:var(--ok);border-color:var(--ok)}
  .b-fail{color:var(--fail);border-color:var(--fail)}
  .act{font:13px ui-monospace,SFMono-Regular,Consolas,monospace;color:var(--text);word-break:break-word}
  .args{color:var(--muted);font:12px ui-monospace,Consolas,monospace;word-break:break-word}
  .obs{display:flex;flex-wrap:wrap;gap:6px 12px;margin-top:8px;font-size:12px}
  .obs span{color:var(--muted)} .obs b{color:var(--text);font-weight:600;font-variant-numeric:tabular-nums}
  .tok{margin-left:auto;color:var(--muted);font:11px ui-monospace,Consolas,monospace;white-space:nowrap}
  .detail{display:none;margin-top:10px;border-top:1px solid var(--border);padding-top:10px}
  .node.open .detail{display:block}
  .detail h4{margin:8px 0 4px;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.05em}
  pre{margin:0;background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:10px;overflow:auto;max-height:340px;font:11px/1.5 ui-monospace,Consolas,monospace;color:#c9d1d9}
  .subflow .card{border-color:#30363d;background:linear-gradient(90deg,rgba(125,133,144,.12),var(--panel))}
  .subflow::before{content:"";position:absolute;left:-6px;top:16px;width:10px;height:10px;background:var(--muted);transform:rotate(45deg);border-radius:2px}
  .mark{color:var(--muted);font:11px ui-monospace,Consolas,monospace}
  .empty{color:var(--muted);padding:30px;text-align:center}
  @media (max-width:640px){.bar input[type=search]{min-width:120px}.tok{margin-left:0}}
</style>
</head>
<body>
<header>
  <h1>Chronicle 决策过程 · {{RUN}}</h1>
  <div class="sub">逐条回放模型在每一步看到的状态、做出的决定与原生后果。生成于 {{GENERATED}}。点击任意卡片展开完整观察与动作目录。</div>
  <div class="summary" id="summary"></div>
  <div class="failure" id="failure"></div>
</header>
<div class="bar">
  <input type="search" id="q" placeholder="搜索动作 / scope / 参数…" aria-label="搜索决策">
  <select id="scope" aria-label="按 scope 筛选"><option value="">全部 scope</option></select>
  <label><input type="checkbox" id="fAction" checked> 动作</label>
  <label><input type="checkbox" id="fClassify" checked> 分类</label>
  <label><input type="checkbox" id="fControl" checked> 控制/停止</label>
  <label><input type="checkbox" id="fSub" checked> 子流程</label>
  <a href="#" id="expandAll">全部展开</a>
</div>
<main>
  <div class="hint" id="hint"></div>
  <div id="timeline"></div>
</main>
<script id="data" type="application/json">{{DATA}}</script>
<script id="verdict" type="application/json">{{VERDICT}}</script>
<script>
(function(){
  const items = JSON.parse(document.getElementById('data').textContent);
  const verdict = JSON.parse(document.getElementById('verdict').textContent);
  const esc = s => String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  const j = o => esc(JSON.stringify(o,null,2));

  // Summary
  const actions = items.filter(x=>x.kind==='decision'&&x.action).length;
  const controls = items.filter(x=>x.kind==='decision'&&x.control).length;
  const classes = items.filter(x=>x.kind==='decision'&&x.classification).length;
  const subs = items.filter(x=>x.kind==='subflow');
  const subsOk = subs.filter(x=>x.status==='completed').length;
  const pt = items.reduce((a,x)=>a+(x.promptTokens||0),0), ct = items.reduce((a,x)=>a+(x.completionTokens||0),0);
  const vp = verdict.passed===true?'v-pass':verdict.passed===false?'v-fail':'v-na';
  const vt = verdict.passed===true?'通过':verdict.passed===false?'未通过':'无收据';
  document.getElementById('summary').innerHTML =
    '<div class="stat"><span>结果</span><span class="verdict '+vp+'">'+vt+'</span></div>'+
    '<div class="stat"><b>'+items.filter(x=>x.kind==='decision').length+'</b><span>模型决策</span></div>'+
    '<div class="stat"><b>'+actions+'</b><span>原生动作</span></div>'+
    '<div class="stat"><b>'+classes+'</b><span>目标分类</span></div>'+
    '<div class="stat"><b>'+controls+'</b><span>控制/停止</span></div>'+
    '<div class="stat"><b>'+subsOk+'/'+subs.length+'</b><span>子流程完成</span></div>'+
    '<div class="stat"><b>'+pt.toLocaleString()+'</b><span>输入 token</span></div>'+
    '<div class="stat"><b>'+ct.toLocaleString()+'</b><span>输出 token</span></div>';
  if(verdict.failure) document.getElementById('failure').textContent='最终失败：'+verdict.failure.replace(/\\n/g,' ');
  document.getElementById('hint').textContent='共 '+items.length+' 个节点 · 子流程里程碑以菱形标记 · 语义色：蓝=动作 紫=分类 黄=控制 绿=成功 红=失败';

  // scope filter options
  const scopes=[...new Set(items.filter(x=>x.scope).map(x=>x.scope))].sort();
  const sel=document.getElementById('scope');
  scopes.forEach(s=>{const o=document.createElement('option');o.value=s;o.textContent=s;sel.appendChild(o)});

  function obsHtml(o){
    if(!o) return '';
    const f=(k,v)=> (v==null||v==='')?'':'<span>'+k+' <b>'+esc(v)+'</b></span>';
    return '<div class="obs">'+f('日',o.campaignDay)+f('状态',o.gameState)+f('菜单',o.menuId)+
      f('金',o.gold)+f('声望',o.renown)+f('人',o.members)+f('健康',o.healthy)+
      f('伤',o.wounded)+f('粮',o.food)+f('位置',o.location)+
      (o.encounter===true?f('遭遇','是'):'')+'</div>';
  }

  function render(x){
    let badge='', act='', detail='';
    if(x.kind==='subflow'){
      const ok=x.status==='completed';
      badge='<span class="badge '+(ok?'b-ok':'b-fail')+'">'+esc(x.status)+'</span>';
      act='<span class="act">'+esc(x.objectiveId)+'</span> <span class="args">'+esc(x.termination)+(x.failureCode?' · '+esc(x.failureCode):'')+'</span>';
      detail='<h4>动作 / 决策 / token</h4><pre>'+j({actionsExecuted:x.actionsExecuted,decisions:x.decisions,promptTokens:x.promptTokens,completionTokens:x.completionTokens,status:x.status,termination:x.termination,failureCode:x.failureCode})+'</pre>';
      return '<div class="node subflow" data-kind="subflow" data-scope="" data-text="'+esc((x.objectiveId||'')+' '+(x.termination||'')+' '+(x.failureCode||''))+'">'+
        '<div class="card" tabindex="0"><div class="row"><span class="num">#'+x.n+'</span>'+badge+
        '<span class="mark">'+esc(x.utc)+'</span><span class="tok">子流程里程碑</span></div>'+
        '<div style="margin-top:6px">'+act+'</div><div class="detail">'+detail+'</div></div></div>';
    }
    if(x.classification){badge='<span class="badge b-classify">分类</span>';act='<span class="act">'+esc(x.classification)+'</span>';}
    else if(x.action){badge='<span class="badge b-action">动作</span>';act='<span class="act">'+esc(x.action)+'</span> <span class="args">'+j(x.arguments)+'</span>';}
    else if(x.control){badge='<span class="badge b-control">'+esc(x.control)+'</span>';act='<span class="args">控制 / 停止</span>';}
    if(x.feedbackKind||x.feedbackCode) badge+=' <span class="badge b-fail">反馈:'+esc(x.feedbackKind||x.feedbackCode)+'</span>';
    detail='<h4>完整观察（模型当时看到的状态）</h4><pre>'+j(x.obsFull)+'</pre>'+
      (x.allowed?'<h4>当前可用动作目录</h4><pre>'+j(x.allowed)+'</pre>':'')+
      '<h4>决策原文</h4><pre>'+j({action:x.action,control:x.control,classification:x.classification,arguments:x.arguments,scope:x.scope,modelId:x.modelId,feedbackKind:x.feedbackKind,feedbackCode:x.feedbackCode})+'</pre>';
    const kind=x.classification?'classify':x.control?'control':'action';
    const text=[x.action,x.control,x.classification,x.scope,j(x.arguments),JSON.stringify(x.obs)].join(' ');
    return '<div class="node" data-kind="'+kind+'" data-scope="'+esc(x.scope||'')+'" data-text="'+esc(text)+'">'+
      '<div class="card" tabindex="0"><div class="row"><span class="num">#'+x.n+'</span>'+badge+
      '<span class="time">'+esc(x.utc)+'</span><span class="badge">'+esc(x.scope||'')+'</span>'+
      '<span class="tok">'+(x.promptTokens||0)+'▲ '+(x.completionTokens||0)+'▼</span></div>'+
      '<div style="margin-top:6px">'+act+'</div>'+obsHtml(x.obs)+'<div class="detail">'+detail+'</div></div></div>';
  }

  const tl=document.getElementById('timeline');
  tl.innerHTML=items.map(render).join('');
  tl.querySelectorAll('.card').forEach(c=>{
    const toggle=()=>c.parentElement.classList.toggle('open');
    c.addEventListener('click',toggle);
    c.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();toggle()}});
  });

  const q=document.getElementById('q'), fAction=document.getElementById('fAction'),
    fClassify=document.getElementById('fClassify'), fControl=document.getElementById('fControl'),
    fSub=document.getElementById('fSub');
  function filter(){
    const term=q.value.trim().toLowerCase(), scope=sel.value;
    const on={action:fAction.checked,classify:fClassify.checked,control:fControl.checked,subflow:fSub.checked};
    let shown=0;
    tl.querySelectorAll('.node').forEach(n=>{
      const k=n.getAttribute('data-kind'), s=n.getAttribute('data-scope')||'', t=(n.getAttribute('data-text')||'').toLowerCase();
      const ok=on[k]&&(!scope||s===scope)&&(!term||t.includes(term));
      n.style.display=ok?'':'none'; if(ok)shown++;
    });
    document.getElementById('hint').textContent='显示 '+shown+' / '+items.length+' 个节点 · 蓝=动作 紫=分类 黄=控制 绿=成功 红=失败';
  }
  [q,sel,fAction,fClassify,fControl,fSub].forEach(el=>el.addEventListener('input',filter));
  document.getElementById('expandAll').addEventListener('click',e=>{
    e.preventDefault();
    const nodes=[...tl.querySelectorAll('.node')].filter(n=>n.style.display!=='none');
    const open=nodes.some(n=>!n.classList.contains('open'));
    nodes.forEach(n=>n.classList.toggle('open',open));
  });
  filter();
})();
</script>
</body>
</html>
'@

$html = $template.Replace('{{RUN}}', $runName).Replace('{{GENERATED}}', $generated).Replace('{{DATA}}', $dataJson).Replace('{{VERDICT}}', $verdictJson)
[IO.File]::WriteAllText($OutputPath, $html, (New-Object Text.UTF8Encoding($false)))
[pscustomobject]@{
    OutputPath = $OutputPath
    RunDirectory = $run
    DecisionCount = @($items | Where-Object { $_.kind -eq 'decision' }).Count
    SubflowCount = @($items | Where-Object { $_.kind -eq 'subflow' }).Count
    Bytes = (Get-Item -LiteralPath $OutputPath).Length
} | ConvertTo-Json -Compress
