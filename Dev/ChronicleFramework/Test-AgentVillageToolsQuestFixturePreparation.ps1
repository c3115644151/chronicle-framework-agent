[CmdletBinding()]
param(
    [string]$SourceSaveName = 'AgentBridgeLifecycle',
    [ValidateRange(1,6)][int]$MaxVillages = 4,
    [int]$TimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$documentsRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)) 'Mount and Blade II Bannerlord'
$sourceSavePath = Join-Path $documentsRoot "Game Saves\$SourceSaveName.sav"
$savePrefix = 'ChronicleW7K-'
$saveName = $savePrefix + [Guid]::NewGuid().ToString('N')
$preparedSavePath = Join-Path $documentsRoot "Game Saves\$saveName.sav"
$sessionPath = Join-Path $documentsRoot 'AgentRuns\ChronicleAgent\session.json'
$sourceHashBefore = (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
$visitedVillageIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$startup = $null
$stop = $null
$failure = $null
$prepared = $false
$marker = $null
$markerSettlementId = $null
$encounterActiveWhileSettlementMenuVisible = $false
$preludeActions = [System.Collections.Generic.List[object]]::new()
$tempRoot = $env:CHRONICLE_HARNESS_TEMP
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE

if (-not (Test-Path -LiteralPath $sourceSavePath -PathType Leaf)) { throw "Disposable Campaign seed is missing: $SourceSaveName" }
if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Refusing to prepare a quest fixture while a Bannerlord process is already running.' }
if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { throw 'Refusing to replace an existing Agent CLI session.' }
if ([string]::IsNullOrWhiteSpace($tempRoot) -or -not (Test-Path -LiteralPath $tempRoot -PathType Container)) { throw 'Quest fixture preparation requires a disposable Harness evidence directory.' }

function Invoke-NativeCli([string]$Action, [string[]]$Arguments = @(), [int]$CallTimeout = 0) {
    $effectiveTimeout = if ($CallTimeout -gt 0) { $CallTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Native fixture-preparation action '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json } catch { throw "Native fixture-preparation action '$Action' returned invalid JSON: $output" }
}

function Get-ToolsIssueMarker($State) {
    foreach ($character in @($State.state.settlementOverlayCharacters)) {
        foreach ($questMarker in @($character.questMarkers)) {
            if ([string]$questMarker.type -ne 'AvailableIssue') { continue }
            $label = [string]$questMarker.title + ' ' + [string]$questMarker.hint
            if ($label -match '(?i)tools?' -or $label.Contains(([char]0x5DE5).ToString() + ([char]0x5177).ToString())) {
                return [pscustomobject]@{ HeroId = [string]$character.heroId; HeroName = [string]$character.name; Title = [string]$questMarker.title; Hint = [string]$questMarker.hint }
            }
        }
    }
    return $null
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $startup = Invoke-NativeCli 'load' @('-SaveName', $SourceSaveName)
    $state = Invoke-NativeCli 'state'
    if ($state.status -ne 'completed' -or $state.state.context.gameState -ne 'MapState') { throw 'Source fixture did not load into Campaign Map state.' }

    if ([int]$state.state.party.members -lt 5) {
        $initialTargets = Invoke-NativeCli 'mapSettlementTargets'
        if ($initialTargets.status -ne 'completed') { throw 'Native map query failed while seeking an observed Town for ordinary escort preparation.' }
        $safeTown = @($initialTargets.data.mapSettlementTargets |
            Where-Object { $_.type -eq 'town' -and -not $_.hostile -and -not $_.underSiege -and [double]$_.distance -gt 1.0 } |
            Sort-Object { [double]$_.distance } | Select-Object -First 1)
        if ($safeTown.Count -eq 1) {
            $townId = [string]$safeTown[0].id
            $townMove = Invoke-NativeCli 'move' @('-SettlementId', $townId)
            if ($townMove.status -eq 'completed' -and [string]$townMove.state.location.targetSettlementId -ceq $townId) {
                $preludeActions.Add([ordered]@{ action='move'; settlementId=$townId; purpose='ordinary Native escort preparation before quest travel'; status=[string]$townMove.status })
                $townDeadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
                do {
                    Start-Sleep -Seconds 1
                    $state = Invoke-NativeCli 'state' @() 45
                    $atTargetTownMenu = [string]$state.state.location.currentSettlementId -ceq $townId -and [string]$state.state.context.menuId -eq 'town'
                    if ([string]$state.state.context.menuId -eq 'encounter_meeting' -or ([bool]$state.state.context.encounterActive -and -not $atTargetTownMenu)) { throw 'A Native encounter menu interrupted escort preparation; no encounter option was selected.' }
                    if ($atTargetTownMenu -and [bool]$state.state.context.encounterActive) { $encounterActiveWhileSettlementMenuVisible = $true }
                    if ($atTargetTownMenu) { break }
                    if (-not [bool]$state.state.party.isMoving) { throw "Native escort preparation travel to '$townId' stopped before arrival." }
                } while ([DateTime]::UtcNow -lt $townDeadline)

                if ([string]$state.state.location.currentSettlementId -ceq $townId -and [string]$state.state.context.menuId -eq 'town') {
                    while ([int]$state.state.party.members -lt 5) {
                        $offers = Invoke-NativeCli 'recruitOptions'
                        if ($offers.status -ne 'completed') { break }
                        $offer = @($offers.data.offers | Where-Object { $_.available -and [int]$_.cost -le ([int]$state.state.economy.gold - 500) } | Sort-Object { [int]$_.cost }, { [int]$_.slot } | Select-Object -First 1)
                        if ($offer.Count -ne 1) { break }
                        $recruit = Invoke-NativeCli 'recruit' @('-OwnerId', [string]$offer[0].ownerId, '-TroopId', [string]$offer[0].troopId, '-VolunteerSlot', [string]$offer[0].slot, '-CommandId', ('w7k-prelude-recruit-' + [Guid]::NewGuid().ToString('N')))
                        if ($recruit.status -ne 'completed' -or -not [bool]$recruit.data.verified) { throw 'Native volunteer recruitment failed during the excluded fixture-safety prelude.' }
                        $state = Invoke-NativeCli 'state'
                        $preludeActions.Add([ordered]@{ action='recruit'; ownerId=[string]$offer[0].ownerId; troopId=[string]$offer[0].troopId; cost=[int]$offer[0].cost; isolatedFixtureSetup=$true; status=[string]$recruit.status })
                    }
                    $leaveTown = @($state.state.availableMenuOptions | Where-Object { $_.isLeave -and $_.available -and $_.enabled } | Select-Object -First 1)
                    if ($leaveTown.Count -eq 1) {
                        $leaveReceipt = Invoke-NativeCli 'menuSelect' @('-MenuId', [string]$state.state.context.menuId, '-OptionId', [string]$leaveTown[0].id)
                        $state = Invoke-NativeCli 'state'
                        $preludeActions.Add([ordered]@{ action='menuSelect'; optionId=[string]$leaveTown[0].id; status=[string]$leaveReceipt.status })
                    }
                }
            }
        }
    }

    for ($attempt = 1; $attempt -le $MaxVillages; $attempt++) {
        if ($state.state.context.menuId -and [string]$state.state.location.currentSettlementId) {
            if ([string]$state.state.context.menuId -notin @('village','town','town_backstreet')) {
                throw "Unexpected settlement menu '$($state.state.context.menuId)' while preparing the native issue fixture."
            }
            $marker = Get-ToolsIssueMarker $state
            if ($marker) { $markerSettlementId = [string]$state.state.location.currentSettlementId; break }
            $leave = @($state.state.availableMenuOptions | Where-Object { $_.isLeave -and $_.available -and $_.enabled } | Select-Object -First 1)
            if ($leave.Count -ne 1) { throw 'No current enabled Native Leave option was available to resume fixture search.' }
            $leaveReceipt = Invoke-NativeCli 'menuSelect' @('-MenuId', [string]$state.state.context.menuId, '-OptionId', [string]$leave[0].id)
            $preludeActions.Add([ordered]@{ action='menuSelect'; optionId=[string]$leave[0].id; status=[string]$leaveReceipt.status })
            $state = Invoke-NativeCli 'state'
        }

        $targets = Invoke-NativeCli 'mapSettlementTargets'
        if ($targets.status -ne 'completed') { throw 'Native map target query failed during the bounded visible-village preparation.' }
        $village = @($targets.data.mapSettlementTargets |
            Where-Object { $_.type -eq 'village' -and -not $_.hostile -and -not $_.underSiege -and [double]$_.distance -gt 1.0 -and $_.id -notin $visitedVillageIds } |
            Sort-Object @{Expression={ if ($_.id -eq 'village_V1_1') { 0 } else { 1 } }}, @{Expression={ [double]$_.distance }} |
            Select-Object -First 1)
        if ($village.Count -ne 1) { break }
        $villageId = [string]$village[0].id
        $visitedVillageIds.Add($villageId) | Out-Null
        $move = Invoke-NativeCli 'move' @('-SettlementId', $villageId)
        if ($move.status -ne 'completed' -or [string]$move.state.location.targetSettlementId -cne $villageId) {
            throw "Native movement did not accept the currently visible safe village '$villageId'."
        }
        $preludeActions.Add([ordered]@{ action='move'; settlementId=$villageId; status=[string]$move.status; campaignDay=[double]$move.campaignDay })

        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        do {
            Start-Sleep -Seconds 1
            $state = Invoke-NativeCli 'state' @() 45
            $atTargetVillageMenu = [string]$state.state.location.currentSettlementId -ceq $villageId -and [string]$state.state.context.menuId -eq 'village'
            if ([string]$state.state.context.menuId -eq 'encounter_meeting' -or ([bool]$state.state.context.encounterActive -and -not $atTargetVillageMenu)) {
                throw 'A Native encounter menu interrupted the bounded fixture-preparation travel; no encounter option was selected.'
            }
            if ($atTargetVillageMenu -and [bool]$state.state.context.encounterActive) { $encounterActiveWhileSettlementMenuVisible = $true }
            if ($atTargetVillageMenu) { break }
            if (-not [bool]$state.state.party.isMoving) { throw "Native movement to '$villageId' stopped before village arrival." }
        } while ([DateTime]::UtcNow -lt $deadline)

        if ([string]$state.state.location.currentSettlementId -cne $villageId -or [string]$state.state.context.menuId -ne 'village') { throw "Native travel to '$villageId' timed out." }
        $marker = Get-ToolsIssueMarker $state
        if ($marker) { $markerSettlementId = $villageId; break }
    }

    if (-not $marker -or -not $markerSettlementId) { throw 'No currently visible Native village tools issue marker was found within the bounded observed-village search; no Quest was injected.' }
    if ([string]$state.state.context.gameState -ne 'MapState' -or [string]$state.state.context.menuId -ne 'village') { throw 'Prepared quest fixture did not end in the visible Native village menu.' }
    $framePath = Join-Path $tempRoot 'VillageToolsQuest-prepared-visible-marker.bmp'
    $frame = Invoke-NativeCli 'captureFrame' @('-OutputPath', $framePath, '-CommandId', ('w7k-fixture-' + [Guid]::NewGuid().ToString('N'))) 45
    if ($frame.status -ne 'completed' -or -not (Test-Path -LiteralPath $framePath) -or (Get-Item -LiteralPath $framePath).Length -lt 4096) { throw 'The game-engine frame for the naturally visible blue tools marker was not captured.' }

    $saveRequest = Invoke-NativeCli 'save' @('-SaveName', $saveName) 120
    if ($saveRequest.status -notin @('accepted', 'completed') -or [string]::IsNullOrWhiteSpace([string]$saveRequest.commandId)) { throw 'Native did not accept the unique disposable StoryMode quest fixture SaveAs.' }
    $responsePath = Join-Path $documentsRoot "AgentRuns\ChronicleAgent\responses\$($saveRequest.commandId).completed.json"
    $saveDeadline = [DateTime]::UtcNow.AddSeconds(120)
    while (-not (Test-Path -LiteralPath $responsePath -PathType Leaf) -and [DateTime]::UtcNow -lt $saveDeadline) { Start-Sleep -Milliseconds 250 }
    if (-not (Test-Path -LiteralPath $preparedSavePath -PathType Leaf) -or -not (Test-Path -LiteralPath $responsePath -PathType Leaf)) { throw 'Native did not finish the disposable quest fixture save.' }
    $saveReceipt = Get-Content -LiteralPath $responsePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($saveReceipt.action -ne 'save' -or $saveReceipt.status -ne 'completed' -or $saveReceipt.processId -ne $startup.session.processId) { throw 'SaveAs completion did not match the active Bannerlord process.' }
    $prepared = $true
}
catch { $failure = $_.Exception.Message }
finally {
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) {
        try { $stop = Invoke-NativeCli 'stop' @() 45 } catch { if (-not $failure) { $failure = "Fixture-preparation game/session cleanup failed: $($_.Exception.Message)" } }
    }
    if (-not $prepared -and -not (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)) {
        $saveRoot = [IO.Path]::GetFullPath((Join-Path $documentsRoot 'Game Saves'))
        $saveRootPrefix = $saveRoot + [IO.Path]::DirectorySeparatorChar
        $candidatePath = [IO.Path]::GetFullPath($preparedSavePath)
        if ($saveName.StartsWith($savePrefix, [StringComparison]::Ordinal) -and $candidatePath.StartsWith($saveRootPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            [IO.File]::Delete($candidatePath)
        }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}

$sourceHashAfter = (Get-FileHash -LiteralPath $sourceSavePath -Algorithm SHA256).Hash
$cleanupPass = [bool]($stop.processStopped -and -not (Test-Path -LiteralPath $sessionPath -PathType Leaf) -and -not (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue))
$result = [ordered]@{
    Prepared = [bool]($prepared -and -not $failure -and $cleanupPass -and $sourceHashBefore -ceq $sourceHashAfter)
    PreparedSaveName = if ($prepared) { $saveName } else { $null }
    SourceSaveName = $SourceSaveName
    SourceHashBefore = $sourceHashBefore
    SourceHashAfter = $sourceHashAfter
    SourceFixtureUnchanged = ($sourceHashBefore -ceq $sourceHashAfter)
    VisibleMarker = if ($marker) { [ordered]@{ settlementId=$markerSettlementId; heroId=$marker.HeroId; heroName=$marker.HeroName; title=$marker.Title; hint=$marker.Hint } } else { $null }
    EncounterActiveWhileSettlementMenuVisible = $encounterActiveWhileSettlementMenuVisible
    PreludeActions = @($preludeActions)
    TimeActionsAreFixturePreparationOnly = @($preludeActions | Where-Object { $_.action -in @('resume') } | ForEach-Object action)
    EngineFramePath = if (Test-Path -LiteralPath (Join-Path $tempRoot 'VillageToolsQuest-prepared-visible-marker.bmp')) { Join-Path $tempRoot 'VillageToolsQuest-prepared-visible-marker.bmp' } else { $null }
    GameProcessStopped = [bool]$cleanupPass
    Failure = $failure
}
$resultPath = Join-Path $tempRoot 'VillageToolsQuestFixturePreparation.json'
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12
if (-not $result.Prepared) { exit 1 }
