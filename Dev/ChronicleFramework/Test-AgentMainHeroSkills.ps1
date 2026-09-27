[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultName = 'MainHeroSkillsResult.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP $resultName } else { Join-Path $PSScriptRoot 'TestResults\ManualMainHeroSkills\MainHeroSkillsResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'main-hero-skills-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "MainHero skill fixture not found: $savePath" }
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
    $before = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before")
    $reference = Invoke-AgentCli 'harnessPlayerSkillsDiagnostics' @('-CommandId', "$commandPrefix-native-skills")
    $afterRead = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after-read")

    $skills = @($before.state.mainHeroSkills)
    $referenceSkills = @($reference.data.skills)
    $skillIds = @($skills | ForEach-Object { [string]$_.id })
    $referenceIds = @($referenceSkills | ForEach-Object { [string]$_.id })
    $uniqueSkillIds = ($skillIds.Count -eq @($skillIds | Select-Object -Unique).Count)
    $skillSetMatches = (@(Compare-Object -ReferenceObject @($referenceIds | Sort-Object) -DifferenceObject @($skillIds | Sort-Object)).Count -eq 0)
    $levelsMatchNative = $true
    foreach ($skill in $skills) {
        $nativeSkill = @($referenceSkills | Where-Object { $_.id -eq $skill.id } | Select-Object -First 1)
        if ($nativeSkill.Count -ne 1 -or [int]$nativeSkill[0].level -ne [int]$skill.level) { $levelsMatchNative = $false; break }
    }
    $hasCrafting = @($skills | Where-Object { $_.id -eq 'Crafting' }).Count -eq 1
    $hasScouting = @($skills | Where-Object { $_.id -eq 'Scouting' }).Count -eq 1
    $beforeSkillsJson = ConvertTo-Json -InputObject @($skills) -Compress -Depth 5
    $afterSkillsJson = ConvertTo-Json -InputObject @($afterRead.state.mainHeroSkills) -Compress -Depth 5
    $stableAcrossReads = [string]::Equals([string]$beforeSkillsJson, [string]$afterSkillsJson, [StringComparison]::Ordinal)
    $snapshotUnchanged = (
        $before.state.identity.heroId -eq $afterRead.state.identity.heroId -and
        $before.state.location.x -eq $afterRead.state.location.x -and
        $before.state.location.y -eq $afterRead.state.location.y -and
        $before.state.party.members -eq $afterRead.state.party.members -and
        $before.state.party.prisoners -eq $afterRead.state.party.prisoners -and
        $before.state.economy.gold -eq $afterRead.state.economy.gold -and
        $before.state.economy.renown -eq $afterRead.state.economy.renown -and
        $before.campaignDay -eq $afterRead.campaignDay -and
        $before.state.context.timeControlMode -eq $afterRead.state.context.timeControlMode
    )
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

    $result = [ordered]@{
        HeroId = $before.state.identity.heroId
        SkillCount = $skills.Count
        NativeReferenceSkillCount = $referenceSkills.Count
        UniqueSkillIds = $uniqueSkillIds
        SkillSetMatchesNative = $skillSetMatches
        LevelsMatchHeroGetSkillValue = $levelsMatchNative
        HasCrafting = $hasCrafting
        HasScouting = $hasScouting
        Skills = $skills
        StableAcrossReads = $stableAcrossReads
        SnapshotUnchanged = $snapshotUnchanged
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = $stop.processStopped
    }
    $assertions = [ordered]@{
        HasSkills = ($skills.Count -gt 0)
        UniqueSkillIds = [bool]$uniqueSkillIds
        SkillSetMatchesNative = [bool]$skillSetMatches
        LevelsMatchHeroGetSkillValue = [bool]$levelsMatchNative
        HasCrafting = [bool]$hasCrafting
        HasScouting = [bool]$hasScouting
        StableAcrossReads = [bool]$stableAcrossReads
        SnapshotUnchanged = [bool]$snapshotUnchanged
        FixtureUnchanged = [bool]$result.FixtureUnchanged
        ProcessStopped = [bool]$result.ProcessStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result.Assertions = $assertions
    $result.FailedAssertions = $failedAssertions
    $result.Passed = ($failedAssertions.Count -eq 0)
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { throw 'MainHero skill observation diverged from native Hero.GetSkillValue or mutated Campaign/save state.' }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
