[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultName = 'SpendSkillFocusResult.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP $resultName } else { Join-Path $PSScriptRoot 'TestResults\ManualSpendSkillFocus\SpendSkillFocusResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'spend-focus-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Skill Focus fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause")
    if ($pause.status -ne 'completed') { throw 'Could not explicitly pause the disposable Campaign fixture.' }

    $beforeState = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before-state")
    $beforeDevelopment = Invoke-AgentCli 'characterDevelopment' @('-CommandId', "$commandPrefix-before-development")
    $beforeNative = Invoke-AgentCli 'harnessCharacterDevelopmentDiagnostics' @('-CommandId', "$commandPrefix-before-native")
    $skillId = 'Crafting'
    $beforeSkill = @($beforeDevelopment.data.skills | Where-Object { $_.id -eq $skillId } | Select-Object -First 1)
    if ($beforeSkill.Count -ne 1) { throw "Fixture does not expose the active skill '$skillId'." }
    if ([int]$beforeDevelopment.data.unspentFocusPoints -lt 3 -or [int]$beforeSkill[0].focus -ne 0) { throw 'Fixture no longer has at least three free Focus points and an uninvested Crafting skill; choose a fresh disposable fixture instead of seeding gameplay state.' }

    $successfulSpend = Invoke-AgentCli 'spendSkillFocus' @('-SkillId', $skillId, '-Count', '1', '-CommandId', "$commandPrefix-spend-one")
    $afterSpendState = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-state")
    $afterSpendDevelopment = Invoke-AgentCli 'characterDevelopment' @('-CommandId', "$commandPrefix-after-development")
    $afterSpendNative = Invoke-AgentCli 'harnessCharacterDevelopmentDiagnostics' @('-CommandId', "$commandPrefix-after-native")
    $afterSkill = @($afterSpendDevelopment.data.skills | Where-Object { $_.id -eq $skillId } | Select-Object -First 1)
    $nativeAfterSkill = @($afterSpendNative.data.skills | Where-Object { $_.id -eq $skillId } | Select-Object -First 1)

    $overBudget = Invoke-AgentCli 'spendSkillFocus' @('-SkillId', $skillId, '-Count', '3', '-CommandId', "$commandPrefix-over-budget")
    $afterOverBudget = Invoke-AgentCli 'characterDevelopment' @('-CommandId', "$commandPrefix-after-over-budget")
    $overCap = Invoke-AgentCli 'spendSkillFocus' @('-SkillId', $skillId, '-Count', '5', '-CommandId', "$commandPrefix-over-cap")
    $afterOverCap = Invoke-AgentCli 'characterDevelopment' @('-CommandId', "$commandPrefix-after-over-cap")
    $afterRejectState = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-reject-state")

    $successCorrect = (
        $successfulSpend.status -eq 'completed' -and
        $successfulSpend.data.skillId -eq $skillId -and
        [int]$successfulSpend.data.requestedCount -eq 1 -and
        [int]$successfulSpend.data.committedCount -eq 1 -and
        [int]$successfulSpend.data.focusBefore -eq [int]$beforeSkill[0].focus -and
        [int]$successfulSpend.data.focusAfter -eq [int]$beforeSkill[0].focus + 1 -and
        [int]$successfulSpend.data.focusPointsBefore -eq [int]$beforeDevelopment.data.unspentFocusPoints -and
        [int]$successfulSpend.data.focusPointsAfter -eq [int]$beforeDevelopment.data.unspentFocusPoints - 1
    )
    $nativeCommitCorrect = (
        $afterSkill.Count -eq 1 -and $nativeAfterSkill.Count -eq 1 -and
        [int]$afterSkill[0].focus -eq [int]$beforeSkill[0].focus + 1 -and
        [int]$afterSpendDevelopment.data.unspentFocusPoints -eq [int]$beforeDevelopment.data.unspentFocusPoints - 1 -and
        [int]$nativeAfterSkill[0].focus -eq [int]$afterSkill[0].focus -and
        [bool]$afterSkill[0].canAddFocus -eq [bool]$nativeAfterSkill[0].canAddFocus -and
        [Math]::Abs([double]$afterSkill[0].learningRate - [double]$nativeAfterSkill[0].learningRate) -lt 0.0001 -and
        [Math]::Abs([double]$successfulSpend.data.learningRateAfter - [double]$afterSkill[0].learningRate) -lt 0.0001
    )
    $overBudgetRejectedWithoutMutation = (
        $overBudget.status -eq 'rejected' -and
        [int]$afterOverBudget.data.unspentFocusPoints -eq [int]$afterSpendDevelopment.data.unspentFocusPoints -and
        [int](@($afterOverBudget.data.skills | Where-Object { $_.id -eq $skillId })[0].focus) -eq [int]$afterSkill[0].focus
    )
    $overCapRejectedWithoutMutation = (
        $overCap.status -eq 'rejected' -and
        [int]$afterOverCap.data.unspentFocusPoints -eq [int]$afterSpendDevelopment.data.unspentFocusPoints -and
        [int](@($afterOverCap.data.skills | Where-Object { $_.id -eq $skillId })[0].focus) -eq [int]$afterSkill[0].focus
    )
    $worldStable = (
        $beforeState.state.identity.heroId -eq $afterRejectState.state.identity.heroId -and
        $beforeState.state.location.x -eq $afterRejectState.state.location.x -and
        $beforeState.state.location.y -eq $afterRejectState.state.location.y -and
        $beforeState.state.party.members -eq $afterRejectState.state.party.members -and
        $beforeState.state.party.prisoners -eq $afterRejectState.state.party.prisoners -and
        $beforeState.state.economy.gold -eq $afterRejectState.state.economy.gold -and
        $beforeState.state.economy.renown -eq $afterRejectState.state.economy.renown -and
        $beforeState.campaignDay -eq $afterRejectState.campaignDay -and
        $afterRejectState.state.context.timeControlMode -eq 'Stop'
    )
    $questsUnchanged = [string](ConvertTo-Json -InputObject @($beforeState.state.quests) -Depth 8 -Compress) -ceq [string](ConvertTo-Json -InputObject @($afterRejectState.state.quests) -Depth 8 -Compress)
    $skillLevelsUnchanged = [string](ConvertTo-Json -InputObject @($beforeState.state.mainHeroSkills) -Depth 8 -Compress) -ceq [string](ConvertTo-Json -InputObject @($afterRejectState.state.mainHeroSkills) -Depth 8 -Compress)

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions = [ordered]@{
        ExplicitPauseEstablished = ($pause.status -eq 'completed' -and $beforeState.state.context.timeControlMode -eq 'Stop')
        SuccessfulSinglePointSpend = [bool]$successCorrect
        NativeHeroDeveloperAndViewModelMatch = [bool]$nativeCommitCorrect
        OverBudgetRequestRejectedAtomically = [bool]$overBudgetRejectedWithoutMutation
        OverCapRequestRejectedAtomically = [bool]$overCapRejectedWithoutMutation
        WorldAndClockUnchangedUnderExplicitPause = [bool]$worldStable
        QuestListUnchanged = [bool]$questsUnchanged
        SkillLevelsUnchanged = [bool]$skillLevelsUnchanged
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        SkillId = $skillId
        FocusBefore = $beforeSkill[0].focus
        FocusAfter = if ($afterSkill.Count -eq 1) { $afterSkill[0].focus } else { $null }
        PointsBefore = $beforeDevelopment.data.unspentFocusPoints
        PointsAfter = $afterSpendDevelopment.data.unspentFocusPoints
        OverBudgetStatus = $overBudget.status
        OverCapStatus = $overCap.status
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { throw 'Skill Focus transaction diverged from native Character Developer results or partially changed a rejected request.' }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
