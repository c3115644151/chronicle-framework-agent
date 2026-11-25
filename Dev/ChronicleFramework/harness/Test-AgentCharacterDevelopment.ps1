#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultName = 'CharacterDevelopmentResult.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP $resultName } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualCharacterDevelopment\CharacterDevelopmentResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'character-development-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Character development fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $before = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-before")
    $observed = Invoke-AgentCli 'characterDevelopment' @('-CommandId', "$commandPrefix-development")
    $reference = Invoke-AgentCli 'harnessCharacterDevelopmentDiagnostics' @('-CommandId', "$commandPrefix-native-view-model")
    $afterRead = Invoke-AgentCli 'characterDevelopment' @('-CommandId', "$commandPrefix-development-again")
    $afterReference = Invoke-AgentCli 'harnessCharacterDevelopmentDiagnostics' @('-CommandId', "$commandPrefix-native-view-model-again")
    $after = Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-after")

    $data = $observed.data
    $native = $reference.data
    $skills = @($data.skills)
    $nativeSkills = @($native.skills)
    $attributes = @($data.attributes)
    $nativeAttributes = @($native.attributes)
    $skillIds = @($skills | ForEach-Object { [string]$_.id })
    $nativeSkillIds = @($nativeSkills | ForEach-Object { [string]$_.id })
    $attributeIds = @($attributes | ForEach-Object { [string]$_.id })
    $nativeAttributeIds = @($nativeAttributes | ForEach-Object { [string]$_.id })
    $skillSetMatches = (@(Compare-Object -ReferenceObject @($nativeSkillIds | Sort-Object) -DifferenceObject @($skillIds | Sort-Object)).Count -eq 0)
    $attributeSetMatches = (@(Compare-Object -ReferenceObject @($nativeAttributeIds | Sort-Object) -DifferenceObject @($attributeIds | Sort-Object)).Count -eq 0)

    $skillValuesMatch = $true
    foreach ($skill in $skills) {
        $nativeSkill = @($nativeSkills | Where-Object { $_.id -eq $skill.id } | Select-Object -First 1)
        if ($nativeSkill.Count -ne 1) { $skillValuesMatch = $false; break }
        $n = $nativeSkill[0]
        if ([string]$skill.name -ne [string]$n.name -or
            [int]$skill.level -ne [int]$n.level -or
            [int]$skill.experienceProgress -ne [int]$n.experienceProgress -or
            [int]$skill.experienceRequiredForNextLevel -ne [int]$n.experienceRequiredForNextLevel -or
            [int]$skill.focus -ne [int]$n.focus -or
            [Math]::Abs([double]$skill.learningRate - [double]$n.learningRate) -gt 0.0001 -or
            [int]$skill.learningLimit -ne [int]$n.learningLimit -or
            [bool]$skill.canAddFocus -ne [bool]$n.canAddFocus -or
            [int]$skill.perks.Count -ne [int](@($n.perks | Where-Object { [int]$_.state -ne 0 }).Count)) { $skillValuesMatch = $false; break }

        $observedPerks = @($skill.perks)
        $nativePerks = @($n.perks | Where-Object { [int]$_.state -ne 0 })
        if (@(Compare-Object -ReferenceObject @($nativePerks | ForEach-Object { [string]$_.id } | Sort-Object) -DifferenceObject @($observedPerks | ForEach-Object { [string]$_.id } | Sort-Object)).Count -ne 0) { $skillValuesMatch = $false; break }
        foreach ($perk in $observedPerks) {
            $nativePerk = @($nativePerks | Where-Object { $_.id -eq $perk.id } | Select-Object -First 1)
            if ($nativePerk.Count -ne 1) { $skillValuesMatch = $false; break }
            $expectedChoiceState = switch ([int]$nativePerk[0].state) {
                2 { 'owned' }
                3 { 'alternativeSelected' }
                1 { 'selectable' }
                4 { 'blockedByPrevious' }
                default { 'unexpected' }
            }
            if ([string]$perk.choiceState -ne $expectedChoiceState -or
                [string]$perk.alternativeId -ne [string]$nativePerk[0].alternativeId -or
                [single]$perk.requiredSkillLevel -ne [single]$nativePerk[0].requiredSkillLevel) { $skillValuesMatch = $false; break }
        }
        if (-not $skillValuesMatch) { break }
    }

    $attributeValuesMatch = $true
    foreach ($attribute in $attributes) {
        $nativeAttribute = @($nativeAttributes | Where-Object { $_.id -eq $attribute.id } | Select-Object -First 1)
        if ($nativeAttribute.Count -ne 1 -or [int]$attribute.value -ne [int]$nativeAttribute[0].value) { $attributeValuesMatch = $false; break }
    }
    $totalsMatch = (
        [string]$data.heroId -eq [string]$native.heroId -and
        [int]$data.level -eq [int]$native.level -and
        [int]$data.totalExperience -eq [int]$native.currentTotalXp -and
        [int]$data.experienceForNextLevel -eq [int]$native.xpRequiredForNextLevel -and
        [int]$data.unspentFocusPoints -eq [int]$native.unspentFocusPoints -and
        [int]$data.unspentAttributePoints -eq [int]$native.unspentAttributePoints
    )
    $stableAcrossReads = (
        [string](ConvertTo-Json -InputObject $data -Depth 12 -Compress) -ceq [string](ConvertTo-Json -InputObject $afterRead.data -Depth 12 -Compress) -and
        [string](ConvertTo-Json -InputObject $native -Depth 12 -Compress) -ceq [string](ConvertTo-Json -InputObject $afterReference.data -Depth 12 -Compress)
    )
    $snapshotUnchanged = (
        $before.state.identity.heroId -eq $after.state.identity.heroId -and
        $before.state.location.x -eq $after.state.location.x -and
        $before.state.location.y -eq $after.state.location.y -and
        $before.state.party.members -eq $after.state.party.members -and
        $before.state.party.prisoners -eq $after.state.party.prisoners -and
        $before.state.economy.gold -eq $after.state.economy.gold -and
        $before.state.economy.renown -eq $after.state.economy.renown -and
        $before.campaignDay -eq $after.campaignDay -and
        $before.state.context.timeControlMode -eq $after.state.context.timeControlMode
    )
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

    $assertions = [ordered]@{
        QueryCompleted = ($observed.status -eq 'completed' -and $null -ne $data)
        HeroMatchesNativeViewModel = [bool]($data.heroId -eq $native.heroId)
        SkillSetMatchesNativeCharacterDeveloper = [bool]$skillSetMatches
        SkillProgressFocusRateAndPerksMatchNativeVM = [bool]$skillValuesMatch
        AttributeSetMatchesNativeCharacterDeveloper = [bool]$attributeSetMatches
        AttributeValuesMatchNativeVM = [bool]$attributeValuesMatch
        PointBalancesAndLevelProgressMatchNativeVM = [bool]$totalsMatch
        StableAcrossRepeatedReads = [bool]$stableAcrossReads
        SnapshotUnchanged = [bool]$snapshotUnchanged
        FixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        HeroId = $data.heroId
        AttributeCount = $attributes.Count
        SkillCount = $skills.Count
        AvailablePerkCount = @($skills | ForEach-Object { $_.perks }).Count
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
    if (-not $result.Passed) { throw 'Character development query diverged from the native Character Developer VM or changed Campaign/save state.' }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
