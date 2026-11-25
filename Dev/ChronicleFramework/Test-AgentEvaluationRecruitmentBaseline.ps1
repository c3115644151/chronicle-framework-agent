#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$Runs = 5,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
if ($Runs -lt 3 -or $Runs -gt 10) { throw 'Baseline runs must be between 3 and 10.' }
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$loop = Join-Path $PSScriptRoot 'Agent-DecisionLoop.ps1'
$provider = Join-Path $PSScriptRoot 'Test-AgentEvaluationBaselineProvider.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw "Disposable evaluation baseline save not found: $savePath" }
if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw 'Refusing to start repeated baseline while a Bannerlord client is already running.' }
if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing to replace an existing Agent session.' }
$sourceHash = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
$goal = 'Recruit one affordable volunteer from the nearest safe visible settlement through the currently available native recruit_volunteers offer.'
$results = [System.Collections.Generic.List[object]]::new()

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

for ($runIndex = 1; $runIndex -le $Runs; $runIndex++) {
    if (Get-Process -Name Bannerlord* -ErrorAction SilentlyContinue) { throw "Baseline run $runIndex found an unexpected active game process." }
    $runPrefix = 'evaluation-baseline-' + $runIndex + '-' + [Guid]::NewGuid().ToString('N')
    $started = $false
    $runStartUtc = [DateTime]::UtcNow
    try {
        $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
        $started = $true
        $before = Invoke-AgentCli 'state' @('-CommandId', "$runPrefix-before")
        if ($before.state.context.gameState -ne 'MapState' -or $before.state.context.encounterActive -or $before.state.location.currentSettlementId) { throw "Baseline run $runIndex did not start in the expected unobstructed world-map state." }
        $loopOutput = & $HarnessPowerShell -NoProfile -File $loop -DecisionProviderPath $provider -Goal $goal -AllowedActionNames 'mapSettlementTargets,move,resume,recruitOptions,recruit' -MaxDecisions 20 -MaxElapsedSeconds 480 -TimeoutSeconds $TimeoutSeconds -CommandPrefix $runPrefix 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Deterministic baseline decision loop failed on run ${runIndex}: $loopOutput" }
        $loopTrace = $loopOutput | ConvertFrom-Json
        if (-not $loopTrace.termination.completedByProvider -or -not $loopTrace.trace[-1].decision.done) { throw "Baseline run $runIndex exhausted its decision budget instead of reaching its completion receipt." }

        $steps = @($loopTrace.trace)
        $targetQuery = @($steps | Where-Object { $_.decision.action -eq 'mapSettlementTargets' -and $_.actionReceipt.status -eq 'completed' })
        $moveSteps = @($steps | Where-Object { $_.decision.action -eq 'move' -and $_.actionReceipt.status -eq 'completed' })
        $waitSteps = @($steps | Where-Object { $_.control.kind -eq 'bounded-observe-again' })
        $offerSteps = @($steps | Where-Object { $_.decision.action -eq 'recruitOptions' -and $_.actionReceipt.status -eq 'completed' })
        $recruitSteps = @($steps | Where-Object { $_.decision.action -eq 'recruit' -and $_.actionReceipt.status -eq 'completed' })
        if ($targetQuery.Count -ne 1 -or $moveSteps.Count -ne 1 -or $offerSteps.Count -ne 1 -or $recruitSteps.Count -ne 1) { throw "Baseline run $runIndex did not complete one query, move, offer check, and recruitment transaction." }
        $targetId = [string]$moveSteps[0].decision.arguments.SettlementId
        $target = @($targetQuery[0].actionReceipt.data.mapSettlementTargets | Where-Object { [string]$_.id -ceq $targetId -and -not $_.hostile -and -not $_.underSiege -and [double]$_.distance -gt 1.0 } | Select-Object -First 1)
        $menuOption = @($offerSteps[0].observationBefore.state.availableMenuOptions | Where-Object { $_.id -eq 'recruit_volunteers' -and $_.available -and $_.enabled } | Select-Object -First 1)
        $offer = @($offerSteps[0].actionReceipt.data.offers | Where-Object { $_.available -and [string]$_.ownerId -ceq [string]$recruitSteps[0].decision.arguments.OwnerId -and [string]$_.troopId -ceq [string]$recruitSteps[0].decision.arguments.TroopId -and [int]$_.slot -eq [int]$recruitSteps[0].decision.arguments.VolunteerSlot -and [int]$_.cost -le [int]$offerSteps[0].observationBefore.state.economy.gold } | Select-Object -First 1)
        $beforeRecruit = $recruitSteps[0].observationBefore.state
        $afterRecruit = $recruitSteps[0].observationAfter.state
        $complete = ($target.Count -eq 1 -and $offerSteps[0].observationBefore.state.location.currentSettlementId -ceq $targetId -and $offerSteps[0].observationBefore.state.context.menuId -in @('town','town_backstreet','village') -and $menuOption.Count -eq 1 -and $offer.Count -eq 1 -and -not [bool]$recruitSteps[0].decision.arguments.ConfirmPartySizeWarning -and [bool]$recruitSteps[0].actionReceipt.data.verified -and [int]$afterRecruit.party.members -eq ([int]$beforeRecruit.party.members + 1) -and [int]$beforeRecruit.economy.gold - [int]$afterRecruit.economy.gold -eq [int]$offer[0].cost)
        if (-not $complete) { throw "Baseline run $runIndex Native outcome did not match the observed target/offer and verified recruitment receipt." }

        $stop = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-stop")
        $started = $false
        $sourceHashAfterRun = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
        $runResult = [ordered]@{
            Run = $runIndex
            Passed = $complete
            SourceHashUnchanged = ($sourceHashAfterRun -ceq $sourceHash)
            ProviderKind = 'deterministic native Baseline; not a real model'
            ProcessId = $start.session.processId
            CampaignDayStart = [double]$before.campaignDay
            CampaignDayEnd = [double]$afterRecruit.campaignDay
            CampaignDaysElapsed = [double]$afterRecruit.campaignDay - [double]$before.campaignDay
            TimeControlModeStart = [string]$before.state.context.timeControlMode
            TimeControlModeMove = [string]$moveSteps[0].actionReceipt.state.context.timeControlMode
            ReobservationsWhileMoving = $waitSteps.Count
            NativeActions = @($steps | Where-Object { $_.actionExecuted } | ForEach-Object { [string]$_.actionReceipt.action })
            TargetSettlementId = $targetId
            TargetSettlementName = [string]$target[0].name
            RecruitOwnerId = [string]$offer[0].ownerId
            RecruitTroopId = [string]$offer[0].troopId
            RecruitSlot = [int]$offer[0].slot
            RecruitCost = [int]$offer[0].cost
            PartyBefore = [int]$beforeRecruit.party.members
            PartyAfter = [int]$afterRecruit.party.members
            GoldBefore = [int]$beforeRecruit.economy.gold
            GoldAfter = [int]$afterRecruit.economy.gold
            WallClockSeconds = [Math]::Round(([DateTime]::UtcNow - $runStartUtc).TotalSeconds, 3)
            ProcessStopped = [bool]$stop.processStopped
        }
        if (-not $runResult.SourceHashUnchanged -or -not $runResult.ProcessStopped) { throw "Baseline run $runIndex changed the source fixture or leaked a game process." }
        $results.Add($runResult)
    }
    finally {
        if ($started -or (Test-Path -LiteralPath $sessionPath -PathType Leaf)) { try { $null = Invoke-AgentCli 'stop' @('-CommandId', "$runPrefix-cleanup") 15 } catch { } }
    }
}

$allPassed = ($results.Count -eq $Runs -and @($results | Where-Object { -not $_.Passed -or -not $_.SourceHashUnchanged -or -not $_.ProcessStopped }).Count -eq 0)
$result = [ordered]@{
    ProviderKind = 'deterministic Native baseline; not a model capability result'
    RunCount = $Runs
    IndependentRuntimeRuns = $Runs
    DistinctCampaignSeeds = 1
    SourceCampaignHash = $sourceHash
    SourceCampaignsUnchanged = (@($results | Where-Object { -not $_.SourceHashUnchanged }).Count -eq 0)
    Passed = $allPassed
    CampaignDaysElapsed = @($results | ForEach-Object { [double]$_.CampaignDaysElapsed })
    WallClockSeconds = @($results | ForEach-Object { [double]$_.WallClockSeconds })
    Results = @($results)
    ThresholdPolicy = 'This is a same-seed deterministic baseline; candidate pass/fail thresholds must be fixed before real-model evaluation. It does not estimate cross-seed generalization.'
}
$json = $result | ConvertTo-Json -Depth 12
if ($env:CHRONICLE_HARNESS_TEMP -and (Test-Path -LiteralPath $env:CHRONICLE_HARNESS_TEMP -PathType Container)) { Set-Content -LiteralPath (Join-Path $env:CHRONICLE_HARNESS_TEMP 'RecruitmentBaseline.json') -Value $json -Encoding UTF8 }
$json
if (-not $allPassed) { exit 1 }
