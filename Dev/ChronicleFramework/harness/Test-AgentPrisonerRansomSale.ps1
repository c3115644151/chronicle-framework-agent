#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'ChronicleW7P-manual-20261101-eyc-complete',
    [ValidateRange(30,900)][int]$ArrivalTimeoutSeconds = 240,
    [ValidateRange(1,40)][int]$MaxSales = 12,
    [int]$TimeoutSeconds = 180
)

# Native prisoner-sale receipt: town -> town_backstreet -> sell_some_prisoners -> Ransom PartyState ->
# one ExecuteTransferSingle per prisoner -> Done commits the native price draft. No model requests.
$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$runDirectory = if ($env:CHRONICLE_HARNESS_TEMP) { Split-Path -Parent $env:CHRONICLE_HARNESS_TEMP } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualPrisonerRansomSale' }
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
$resultPath = Join-Path $runDirectory 'PrisonerRansomSaleResult.json'
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'prisoner-ransom-sale-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Prisoner ransom sale fixture not found: $savePath" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Get-State([string]$Tag, [int]$CommandTimeout = 0) {
    return Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-$Tag-$([Guid]::NewGuid().ToString('N'))") $CommandTimeout
}

function Get-PrisonerTotal($PartyScreen) {
    $total = 0
    foreach ($row in @($PartyScreen.rightPrisoners)) { if ($row) { $total += [int]$row.count } }
    return $total
}

function Get-FirstSellableRow($PartyScreen) {
    return @($PartyScreen.rightPrisoners | Where-Object { $_.troopId -and [int]$_.count -gt 0 -and $_.transferable } | Sort-Object { [int]$_.count } -Descending | Select-Object -First 1)
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $initial = Get-State 'initial'
    if ($initial.state.context.gameState -ne 'MapState') { throw "Prisoner ransom sale fixture must start on the campaign map; got $($initial.state.context.gameState)." }
    if ($null -ne $initial.state.partyScreen) { throw "Prisoner ransom sale fixture must start with no party screen open; got mode $($initial.state.partyScreen.mode)." }

    $goldBefore = [int]$initial.state.economy.gold
    $prisonersBefore = [int]$initial.state.party.prisoners
    if ($prisonersBefore -lt 1) { throw 'Prisoner ransom sale fixture has no party prisoners to sell.' }

    $travelled = $false
    $arrived = $initial
    if ($initial.state.context.menuId -eq 'town' -and -not [string]::IsNullOrWhiteSpace([string]$initial.state.location.currentSettlementId)) {
        $townId = [string]$initial.state.location.currentSettlementId
    } else {
        $settlement = @($initial.state.nearbySettlements | Where-Object { $_.type -eq 'town' -and -not $_.hostile } | Sort-Object distance | Select-Object -First 1)
        if ($settlement.Count -ne 1) { throw 'No visible non-hostile town exists in the prisoner ransom sale fixture.' }
        $townId = [string]$settlement[0].id
        $move = Invoke-AgentCli 'move' @('-SettlementId', $townId, '-CommandId', "$commandPrefix-move")
        if ($move.status -ne 'completed' -or [string]$move.state.location.targetSettlementId -ne $townId) { throw 'Native campaign map movement did not accept the visible town target.' }
        $travelled = $true
        $arrivalDeadline = [DateTime]::UtcNow.AddSeconds($ArrivalTimeoutSeconds)
        $arrived = $null
        while ([DateTime]::UtcNow -lt $arrivalDeadline) {
            $arrived = Get-State 'arrival' 30
            if ([string]$arrived.state.location.currentSettlementId -eq $townId -and $arrived.state.context.menuId -eq 'town') { break }
            if ($arrived.state.context.encounterActive -and [string]$arrived.state.context.encounteredPartyId -ne $townId) {
                throw "Unexpected encounter '$($arrived.state.context.encounteredPartyId)' interrupted travel to the town."
            }
            if (-not (Get-Process -Id $start.session.processId -ErrorAction SilentlyContinue)) { throw 'Game process exited during natural travel to the town.' }
            Start-Sleep -Milliseconds 500
        }
        if (-not $arrived -or [string]$arrived.state.location.currentSettlementId -ne $townId -or $arrived.state.context.menuId -ne 'town') {
            throw "Natural campaign travel did not enter the town menu within $ArrivalTimeoutSeconds seconds."
        }
    }

    $districtOption = @($arrived.state.availableMenuOptions | Where-Object { $_.id -eq 'town_backstreet' -and $_.available -and $_.enabled })
    if ($districtOption.Count -ne 1) { throw 'Native Town menu did not expose an enabled tavern-district option.' }
    $backstreet = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town', '-OptionId', 'town_backstreet', '-CommandId', "$commandPrefix-backstreet")
    if ($backstreet.status -ne 'completed' -or $backstreet.state.context.menuId -ne 'town_backstreet' -or $backstreet.state.context.gameState -ne 'MapState') {
        throw 'Selecting the tavern district menu option did not enter town_backstreet.'
    }

    $saleOption = @($backstreet.state.availableMenuOptions | Where-Object { $_.id -eq 'sell_some_prisoners' -and $_.available -and $_.enabled })
    if ($saleOption.Count -ne 1) {
        $visible = (@($backstreet.state.availableMenuOptions | ForEach-Object { [string]$_.id }) -join ',')
        throw "Native town_backstreet did not expose a selectable sell_some_prisoners option; visible options: $visible"
    }
    $open = Invoke-AgentCli 'menuSelect' @('-MenuId', 'town_backstreet', '-OptionId', 'sell_some_prisoners', '-CommandId', "$commandPrefix-open-ransom")
    if ($open.status -ne 'completed' -or $open.state.context.gameState -ne 'PartyState' -or $open.state.partyScreen.mode -ne 'Ransom') {
        throw "Selecting sell_some_prisoners did not open the native Ransom PartyState; got $($open.state.context.gameState)/$($open.state.partyScreen.mode)."
    }
    if ([string]$open.state.partyScreen.rightPartyId -ne [string]$initial.state.party.id) {
        throw 'The native Ransom screen does not carry MainParty prisoners on its right side.'
    }

    $draftAtOpen = [double]$open.state.partyScreen.ransomGoldChangeAmount
    $sales = [System.Collections.Generic.List[object]]::new()
    $prisonerTotalAtOpen = Get-PrisonerTotal $open.state.partyScreen
    if ($prisonerTotalAtOpen -lt 1) { throw 'The native Ransom screen exposed no MainParty prisoner rows to sell.' }
    $draftAfterSales = 0.0
    $current = $open
    $saleLimit = [Math]::Min([Math]::Min($MaxSales, $prisonerTotalAtOpen), $prisonersBefore)
    for ($index = 0; $index -lt $saleLimit; $index++) {
        $row = @(Get-FirstSellableRow $current.state.partyScreen)
        if ($row.Count -ne 1) { break }
        $troopId = [string]$row[0].troopId
        $receipt = Invoke-AgentCli 'sellPrisonerOne' @('-TroopId', $troopId, '-CommandId', "$commandPrefix-sell-$index")
        if ($receipt.status -ne 'completed' -or [int]$receipt.data.transferredCount -ne 1) {
            throw "Native ExecuteTransferSingle did not transfer exactly one prisoner for '$troopId'."
        }
        if ([int]$receipt.data.sourceCountAfter -ne ([int]$receipt.data.sourceCountBefore - 1) -or [int]$receipt.data.saleCountAfter -ne ([int]$receipt.data.saleCountBefore + 1)) {
            throw "Native sale roster did not move exactly one '$troopId' into the buyer side."
        }
        $sales.Add([pscustomobject]@{ troopId = $troopId; receipt = $receipt.data })
        $draftAfterSales = [double]$receipt.data.nativeGoldChangeAfter
        $current = Get-State "after-sale-$index" 30
        if ($current.state.context.gameState -ne 'PartyState' -or $current.state.partyScreen.mode -ne 'Ransom') { break }
    }

    if ($sales.Count -lt 1) { throw 'No prisoner was transferred into the native sale roster.' }
    $selectedCount = Get-PrisonerTotal $current.state.partyScreen
    $selectedTotal = @($current.state.partyScreen.leftPrisoners | ForEach-Object { [int]$_.count } | Measure-Object -Sum).Sum
    if ([int]$selectedTotal -ne $sales.Count) { throw "The native sale roster holds $selectedTotal prisoners but the harness transferred $($sales.Count)." }
    if ($draftAfterSales -le 0) { throw "The native sale draft stayed at $draftAfterSales after $($sales.Count) transferred prisoners." }
    if (-not [bool]$current.state.partyScreen.canDone) { throw 'The native Ransom PartyScreen Done control is not available with prisoners in the sale roster.' }

    $done = Invoke-AgentCli 'partyScreenDone' @('-CommandId', "$commandPrefix-done")
    $afterDone = Get-State 'after-done' 30
    $goldAfter = [int]$afterDone.state.economy.gold
    $prisonersAfter = [int]$afterDone.state.party.prisoners

    $assertions = [ordered]@{
        RansomScreenOpenedFromTownBackstreet = ($open.state.partyScreen.mode -eq 'Ransom' -and [double]$open.state.partyScreen.ransomGoldChangeAmount -eq 0)
        TransferOnlyPricedPrisoners = ($sales.Count -ge 1 -and [int]$selectedTotal -eq $sales.Count)
        DraftIsNativeGoldChange = ($draftAfterSales -gt 0)
        DoneCommittedNativeTransaction = ([bool]$done.data.postconditionPassed -and [int]$done.data.selectedCount -eq $sales.Count)
        CommittedGoldMatchesDraft = ([int]$done.data.nativeTransactionAmount -eq [int]$draftAfterSales)
        DoneDidNotAdvanceCampaignTime = ([Math]::Abs([double]$done.data.campaignDayAfter - [double]$done.data.campaignDayBefore) -le 0.000001)
        PartyScreenClosedByDone = [bool]$done.data.partyScreenClosed
        ObservedGoldRaisedBySale = ($goldAfter - $goldBefore -eq [int]$done.data.nativeTransactionAmount)
        ObservedPrisonersReducedBySale = ($prisonersBefore - $prisonersAfter -eq $sales.Count)
        FormalFixtureUnchanged = $true
        ProcessStopped = $true
    }

    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions['FormalFixtureUnchanged'] = ($fixtureHashBefore -eq $fixtureHashAfter)
    $assertions['ProcessStopped'] = [bool]$stop.processStopped

    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        Fixture = [ordered]@{ saveName = $LoadSaveName; sha256Before = $fixtureHashBefore; sha256After = $fixtureHashAfter; travelledToTown = $travelled; townId = $townId }
        Before = [ordered]@{ gold = $goldBefore; prisoners = $prisonersBefore; campaignDay = $initial.state.campaignDay }
        RansomScreen = [ordered]@{ mode = [string]$open.state.partyScreen.mode; rightPartyId = [string]$open.state.partyScreen.rightPartyId; draftGoldAtOpen = $draftAtOpen; prisonerRowsAtOpen = @($open.state.partyScreen.rightPrisoners) }
        Sales = @($sales)
        SaleDraftGold = $draftAfterSales
        DoneReceipt = $done.data
        After = [ordered]@{ gold = $goldAfter; prisoners = $prisonersAfter; campaignDay = $afterDone.state.campaignDay; menuId = [string]$afterDone.state.context.menuId }
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 12
    if (-not $result.Passed) { throw "Native prisoner sale did not raise gold by the committed draft, reduce prisoners by the sold count, or preserve the disposable fixture. Failed: $($failedAssertions -join ', ')" }
}
finally {
    if (Test-Path $sessionPath) {
        try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null } catch { }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
