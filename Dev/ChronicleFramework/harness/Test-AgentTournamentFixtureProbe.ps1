#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'ChronicleEycDev-20261106231339-381d46ee',
    [ValidateRange(20,180)][int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$documentsRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)) 'Mount and Blade II Bannerlord'
$savePath = Join-Path (Join-Path $documentsRoot 'Game Saves') "$LoadSaveName.sav"
$sessionPath = Join-Path $documentsRoot 'AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\TournamentFixtureProbe' }
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'TournamentFixtureProbe.json' } else { Join-Path $runDirectory 'TournamentFixtureProbe.json' }
$commandPrefix = 'tournament-fixture-probe-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
if (-not (Test-Path -LiteralPath $savePath)) { throw "Fixture not found: $LoadSaveName" }
$hashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $attemptId = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $runDirectory "Cli-$Action-$attemptId.stdout.log"
    $stderrPath = Join-Path $runDirectory "Cli-$Action-$attemptId.stderr.log"
    $argumentLine = (@('-NoProfile','-File',$cli,$Action) + $Arguments + @('-TimeoutSeconds',[string]$effectiveTimeout,'-AsJson') | ForEach-Object {
        $value = [string]$_
        if ($value -match '\s|"') { '"' + $value.Replace('"','\"') + '"' } else { $value }
    }) -join ' '
    $proc = Start-Process -FilePath $HarnessPowerShell -ArgumentList $argumentLine -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    if (-not $proc.WaitForExit([Math]::Max(300,$effectiveTimeout+45)*1000)) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; throw "Agent CLI '$Action' timed out" }
    $proc.WaitForExit()
    $output = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 } else { '' }
    try { $result = $output | ConvertFrom-Json } catch { throw "Agent CLI '$Action' invalid JSON: $output" }
    if ([string]$result.status -ne 'completed') { throw "Agent CLI '$Action' not completed: $output" }
    return $result
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName',$LoadSaveName,'-IncludeChronicleFramework')
    $initial = Invoke-AgentCli 'state' @('-CommandId',"$commandPrefix-initial")
    $result = [ordered]@{
        LoadSaveName = $LoadSaveName
        InitialGameState = [string]$initial.state.context.gameState
        InitialSettlement = [string]$initial.state.location.currentSettlementId
        InitialMenu = [string]$initial.state.context.menuId
        InitialNearbySettlements = @($initial.state.nearbySettlements | ForEach-Object { [ordered]@{ id=$_.id; name=$_.name; type=$_.type; distance=$_.distance } })
    }
    $arenaEntered = $false
    $townId = $null
    if ([string]$initial.state.context.gameState -eq 'MapState') {
        if ([string]$initial.state.context.menuId -ceq 'town' -and -not [string]::IsNullOrWhiteSpace([string]$initial.state.location.currentSettlementId)) {
            $townId = [string]$initial.state.location.currentSettlementId
        } else {
            $targets = Invoke-AgentCli 'mapSettlementTargets' @('-CommandId',"$commandPrefix-targets")
            $town = @($targets.data.mapSettlementTargets | Where-Object { [string]$_.type -ceq 'town' -and -not [bool]$_.hostile -and -not [bool]$_.underSiege } | Sort-Object { [double]$_.distance } | Select-Object -First 1)
            if ($town.Count -eq 1) {
                $townId = [string]$town[0].id
                $move = Invoke-AgentCli 'move' @('-SettlementId',$townId,'-CommandId',"$commandPrefix-move") 90
                $deadline = [DateTime]::UtcNow.AddSeconds(120)
                while ([DateTime]::UtcNow -lt $deadline) {
                    $arrived = Invoke-AgentCli 'state' @('-CommandId',"$commandPrefix-arr-$([Guid]::NewGuid().ToString('N'))") 20
                    if ([string]$arrived.state.context.menuId -ceq 'town' -and [string]$arrived.state.location.currentSettlementId -ceq $townId) { break }
                    if ([string]$arrived.state.context.gameState -ne 'MapState') { break }
                    Start-Sleep -Milliseconds 800
                }
                $afterMove = Invoke-AgentCli 'state' @('-CommandId',"$commandPrefix-aftermove")
                $result.MoveResult = [ordered]@{ target=[string]$townId; gameState=[string]$afterMove.state.context.gameState; menu=[string]$afterMove.state.context.menuId; settlement=[string]$afterMove.state.location.currentSettlementId; campaignDay=[double]$afterMove.campaignDay }
            }
        }
    }
    $result.ChosenTown = $townId
    if (-not [string]::IsNullOrWhiteSpace($townId)) {
        $stateNow = Invoke-AgentCli 'state' @('-CommandId',"$commandPrefix-townstate")
        if ([string]$stateNow.state.context.gameState -eq 'MapState' -and [string]$stateNow.state.context.menuId -ceq 'town') {
            $menuOpts = @($stateNow.state.availableMenuOptions | ForEach-Object { [string]$_.id })
            $result.TownMenuOptions = $menuOpts
            if ($menuOpts -contains 'town_arena') {
                $menu = Invoke-AgentCli 'menuSelect' @('-MenuId','town','-OptionId','town_arena','-CommandId',"$commandPrefix-arena")
                $enterOpts = @($menu.state.availableMenuOptions | ForEach-Object { [string]$_.id })
                $result.ArenaMenuOptions = $enterOpts
                if ($enterOpts -contains 'town_enter_arena') {
                    $enter = Invoke-AgentCli 'menuSelect' @('-MenuId','town_arena','-OptionId','town_enter_arena','-CommandId',"$commandPrefix-enter")
                    $arenaEntered = ([string]$enter.state.context.gameState -eq 'MissionState')
                    $result.ArenaScene = [string]$enter.state.mission.sceneName
                }
            }
        }
    }
    $result.ArenaEntered = $arenaEntered
    if ($arenaEntered) {
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        $observed = $null
        $master = @()
        while ([DateTime]::UtcNow -lt $deadline) {
            $observed = Invoke-AgentCli 'state' @('-CommandId',"$commandPrefix-obs-$([Guid]::NewGuid().ToString('N'))") 20
            $master = @($observed.state.mission.nearbySceneAgents | Where-Object { $_.occupation -eq 'ArenaMaster' -and $_.isInteractable })
            if ($master.Count -gt 0 -and [bool]$observed.state.mission.nativeConversationReady) { break }
            Start-Sleep -Milliseconds 500
        }
        $result.ArenaMasters = @($master | ForEach-Object { [ordered]@{ agentIndex=$_.agentIndex; characterId=$_.characterId; name=$_.name; occupation=$_.occupation } })
        if ($master.Count -gt 0 -and [int]$master[0].agentIndex -ge 0) {
            $interact = Invoke-AgentCli 'missionInteract' @('-AgentIndex',[string]$master[0].agentIndex,'-CommandId',"$commandPrefix-interact")
            $after = Invoke-AgentCli 'state' @('-CommandId',"$commandPrefix-after")
            $result.InteractionReceipt = $interact.data
            $result.ConversationCharacter = [string]$after.state.context.conversation.characterId
            $result.ConversationOptions = @($after.state.context.conversation.options | ForEach-Object { [ordered]@{ id=$_.id; text=$_.text; clickable=$_.clickable } })
            $signUp = @($after.state.context.conversation.options | Where-Object { [string]$_.id -eq 'arena_master_sign_up_tournament' -and [bool]$_.clickable })
            if ($signUp.Count -eq 1) {
                $enroll = Invoke-AgentCli 'dialogueSelect' @('-OptionId','arena_master_sign_up_tournament','-CommandId',"$commandPrefix-enroll")
                $enrollState = Invoke-AgentCli 'state' @('-CommandId',"$commandPrefix-enrollstate")
                $result.SignUpReceipt = [ordered]@{ status=[string]$enroll.status; gameState=[string]$enrollState.state.context.gameState; menu=[string]$enrollState.state.context.menuId }
                $result.TournamentAfterSignUp = $enrollState.state.context.tournament
                $result.ConversationAfterSignUp = $enrollState.state.context.conversation
                $confirm = @($enrollState.state.context.conversation.options | Where-Object { [string]$_.id -eq 'arena_master_enter_tournament_confirm' -and [bool]$_.clickable })
                if ($confirm.Count -eq 1) {
                    $enterTourney = Invoke-AgentCli 'dialogueSelect' @('-OptionId','arena_master_enter_tournament_confirm','-CommandId',"$commandPrefix-enter-tourney")
                    $tourneyState = Invoke-AgentCli 'state' @('-CommandId',"$commandPrefix-tourneystate")
                    $result.EnterTournamentReceipt = [ordered]@{ status=[string]$enterTourney.status; gameState=[string]$tourneyState.state.context.gameState; menu=[string]$tourneyState.state.context.menuId; scene=[string]$tourneyState.state.mission.sceneName }
                    $result.TournamentAfterConfirm = $tourneyState.state.context.tournament
                    $result.ConversationAfterConfirm = $tourneyState.state.context.conversation
                    $result.TournamentJoinMenuOptions = @($tourneyState.state.availableMenuOptions | ForEach-Object { [ordered]@{ id=$_.id; text=$_.text; enabled=$_.enabled; clickable=$_.clickable } })
                    if ([string]$tourneyState.state.context.menuId -ceq 'menu_town_tournament_join') {
                        $joinOpts = @($tourneyState.state.availableMenuOptions | Where-Object { [string]$_.id -notlike '*back*' -and [string]$_.id -notlike '*leave*' -and [bool]$_.enabled -ne $false })
                        $result.TournamentJoinCandidates = @($joinOpts | ForEach-Object { [string]$_.id })
                        foreach($opt in $joinOpts){
                            $pick = Invoke-AgentCli 'menuSelect' @('-MenuId','menu_town_tournament_join','-OptionId',[string]$opt.id,'-CommandId',"$commandPrefix-join-$([Guid]::NewGuid().ToString('N'))")
                            $afterPick = Invoke-AgentCli 'state' @('-CommandId',"$commandPrefix-afterpick")
                            $afterPickTourney = $afterPick.state.context.tournament
                            if ($afterPickTourney -and [bool]$afterPickTourney.available -eq $true) {
                                $result.TournamentActivatedVia = [string]$opt.id
                                $result.TournamentActive = $afterPickTourney
                                $result.ActiveGameState = [string]$afterPick.state.context.gameState
                                $result.ActiveScene = [string]$afterPick.state.mission.sceneName
                                break
                            }
                        }
                    }
                }
            }
        }
    }
    $stop = Invoke-AgentCli 'stop' @('-CommandId',"$commandPrefix-stop") 30
    $result.FixtureUnchanged = ((Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash -eq $hashBefore)
    $result.ProcessStopped = [bool]$stop.processStopped
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 12
}
catch {
    $failure = [ordered]@{ ErrorMessage=$_.Exception.Message; LoadSaveName=$LoadSaveName }
    $failure | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDirectory 'TournamentFixtureProbe-failure.json') -Encoding UTF8
    throw
}
finally {
    if (Test-Path $sessionPath) { try { Invoke-AgentCli 'stop' @('-CommandId',"$commandPrefix-cleanup") 20 | Out-Null } catch {} }
    $owned = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Bannerlord*' -and $_.CommandLine -like "*/continuesave $LoadSaveName *" })
    foreach($p in $owned){ Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue }
    $deadline=[DateTime]::UtcNow.AddSeconds(15)
    while((Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 250}
    if(-not (Get-Process -Name 'Bannerlord*' -ErrorAction SilentlyContinue)){ try{ Invoke-AgentCli 'recoverTestConfig' @() 20 | Out-Null }catch{} }
}
