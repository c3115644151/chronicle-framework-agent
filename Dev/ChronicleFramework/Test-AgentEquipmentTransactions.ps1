[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'EquipmentTransactionResult.json' } else { Join-Path $PSScriptRoot 'TestResults\ManualEquipmentTransactions\EquipmentTransactionResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'equipment-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Equipment transaction fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Agent CLI '$Action' failed: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "Agent CLI '$Action' returned invalid JSON: $output" }
}

function Get-State([string]$Suffix) {
    return Invoke-AgentCli 'state' @('-CommandId', "$commandPrefix-$Suffix")
}

function Wait-State([string]$Expected, [int]$Seconds = 10) {
    $until = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $current = Get-State "wait-$Expected-$([Guid]::NewGuid().ToString('N'))"
        if ($current.state.context.gameState -eq $Expected) { return $current }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $until)
    throw "Expected $Expected but last state was $($current.state.context.gameState)."
}

function Open-Inventory([string]$Suffix) {
    $open = Invoke-AgentCli 'inventoryOpen' @('-CommandId', "$commandPrefix-$Suffix-open")
    $state = Wait-State 'InventoryState'
    $options = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-$Suffix-options")
    if ($open.status -ne 'completed' -or $options.status -ne 'completed' -or -not $options.data.isMainHeroSelected)
        { throw "$Suffix did not open/read the native MainHero Inventory VM." }
    return [pscustomobject]@{ Open = $open; State = $state; Options = $options }
}

function Find-EquipmentSlot($Options, [int]$Index) {
    return @($Options.data.equipmentSlots | Where-Object { [int]$_.equipmentIndex -eq $Index } | Select-Object -First 1)[0]
}

function Find-InventoryElement($Options, [string]$ItemId, [string]$ModifierId) {
    $matches = @($Options.data.rightItems | Where-Object {
        $_.inventorySide -eq 'PlayerInventory' -and [string]$_.itemId -eq $ItemId -and [string]$_.modifierId -eq $ModifierId
    })
    if ($matches.Count -gt 1) { throw "Native Inventory contains ambiguous item rows for $ItemId/$ModifierId." }
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

try {
    $env:CHRONICLE_HARNESS_MODE = 'visual-capture'
    $start = Invoke-AgentCli 'load' @('-SaveName', $LoadSaveName)
    $pause = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause-initial")
    $mapBefore = Get-State 'map-before'
    if ($mapBefore.state.context.gameState -ne 'MapState' -or $pause.status -ne 'completed') { throw 'Equipment test did not reach a stopped Campaign Map.' }

    $opened = Open-Inventory 'unequip'
    $occupiedSlot = @($opened.Options.data.equipmentSlots | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.itemId) } | Select-Object -First 1)
    if ($occupiedSlot.Count -ne 1) { throw 'Native MainHero SPInventoryVM exposes no equipped item in the current equipment mode.' }
    $slotIndex = [int]$occupiedSlot[0].equipmentIndex
    $originalItemId = [string]$occupiedSlot[0].itemId
    $originalModifierId = [string]$occupiedSlot[0].modifierId
    $mode = [string]$opened.Options.data.equipmentMode

    $unequipDraft = Invoke-AgentCli 'unequipHeroItem' @('-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-unequip-draft")
    $afterUnequipDraft = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-after-unequip-draft")
    $slotDuringDraft = Find-EquipmentSlot $afterUnequipDraft $slotIndex
    $itemInInventoryDuringDraft = Find-InventoryElement $afterUnequipDraft $originalItemId $originalModifierId
    $unequipDraftPassed = (
        $unequipDraft.status -eq 'completed' -and [bool]$unequipDraft.data.draftCreatedByNativeVM -and
        [string]::IsNullOrWhiteSpace([string]$slotDuringDraft.itemId) -and $null -ne $itemInInventoryDuringDraft
    )
    if (-not $unequipDraftPassed) { throw 'Native SPInventoryVM unequip did not show the expected uncommitted slot/inventory preview.' }

    $unequipCommit = Invoke-AgentCli 'inventoryConfirm' @('-CommandId', "$commandPrefix-unequip-confirm")
    if ($unequipCommit.status -ne 'completed' -or -not $unequipCommit.data.committed -or -not $unequipCommit.data.postconditionPassed)
        { throw 'Native Gauntlet Done did not commit the unequip transfer and postconditions.' }

    $reopened = Open-Inventory 'reequip'
    $itemToEquip = Find-InventoryElement $reopened.Options $originalItemId $originalModifierId
    if ($null -eq $itemToEquip -or [string]::IsNullOrWhiteSpace([string]$itemToEquip.viewModelItemId))
        { throw 'The unequipped EquipmentElement was not available as a native PlayerInventory item after Done.' }
    $equipDraft = Invoke-AgentCli 'equipHeroItem' @('-ItemViewModelId', [string]$itemToEquip.viewModelItemId, '-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-equip-draft")
    $afterEquipDraft = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-after-equip-draft")
    $slotAfterEquipDraft = Find-EquipmentSlot $afterEquipDraft $slotIndex
    $equipDraftPassed = ($equipDraft.status -eq 'completed' -and [bool]$equipDraft.data.draftCreatedByNativeVM -and [string]$slotAfterEquipDraft.itemId -eq $originalItemId -and [string]$slotAfterEquipDraft.modifierId -eq $originalModifierId)
    if (-not $equipDraftPassed) { throw 'Native SPInventoryVM equip did not show the expected uncommitted Equipment preview.' }
    $equipCommit = Invoke-AgentCli 'inventoryConfirm' @('-CommandId', "$commandPrefix-equip-confirm")
    if ($equipCommit.status -ne 'completed' -or -not $equipCommit.data.committed -or -not $equipCommit.data.postconditionPassed)
        { throw 'Native Gauntlet Done did not commit the equip transfer and postconditions.' }

    $cancelTestInventory = Open-Inventory 'cancel'
    $cancelSlot = Find-EquipmentSlot $cancelTestInventory.Options $slotIndex
    if ([string]$cancelSlot.itemId -ne $originalItemId -or [string]$cancelSlot.modifierId -ne $originalModifierId)
        { throw 'MainHero native Equipment state did not retain the equipped item before Cancel test.' }
    $cancelDraft = Invoke-AgentCli 'unequipHeroItem' @('-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-cancel-draft")
    if ($cancelDraft.status -ne 'completed' -or -not $cancelDraft.data.draftCreatedByNativeVM) { throw 'Cancel test did not create a Native Inventory draft.' }
    $cancel = Invoke-AgentCli 'inventoryCancelChanges' @('-CommandId', "$commandPrefix-cancel-changes")
    if ($cancel.status -ne 'completed' -or -not $cancel.data.discardConfirmed -or -not $cancel.data.returnedToMap)
        { throw 'Native Cancel Changes inquiry was not confirmed and returned to the Map.' }

    $afterCancelInventory = Open-Inventory 'after-cancel'
    $slotAfterCancel = Find-EquipmentSlot $afterCancelInventory.Options $slotIndex
    $afterCancel = Invoke-AgentCli 'inventoryCancel' @('-CommandId', "$commandPrefix-close-after-cancel")
    $invalidOpen = Open-Inventory 'invalid'
    $invalidItem = Invoke-AgentCli 'equipHeroItem' @('-ItemViewModelId', 'chronicle_invalid_item_vm_id', '-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-invalid-item")
    $invalidAfter = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-invalid-after")
    $invalidSlotItem = @($invalidAfter.data.equipmentSlots | Where-Object { [int]$_.equipmentIndex -eq $slotIndex } | Select-Object -First 1)[0]
    $invalidNoMutation = ($invalidItem.status -eq 'rejected' -and [string]$invalidSlotItem.itemId -eq $originalItemId -and [string]$invalidSlotItem.modifierId -eq $originalModifierId)
    $invalidCancel = Invoke-AgentCli 'inventoryCancel' @('-CommandId', "$commandPrefix-close-invalid")

    $pauseEnd = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause-end")
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $assertions = [ordered]@{
        OriginalEntryOpenedNativeInventoryState = [bool]$opened.Open.data.inventoryStateActive
        MainHeroEquipmentReadFromNativeVM = [bool]$opened.Options.data.isMainHeroSelected
        NativeUnequipTransferDraftMatchesState = [bool]$unequipDraftPassed
        NativeDoneCommittedUnequip = ([bool]$unequipCommit.data.committed -and [bool]$unequipCommit.data.postconditionPassed)
        NativeEquipTransferDraftMatchesState = [bool]$equipDraftPassed
        NativeDoneCommittedEquip = ([bool]$equipCommit.data.committed -and [bool]$equipCommit.data.postconditionPassed)
        NativeCancelConfirmationDiscardedDraft = ($cancel.data.discardConfirmed -and $slotAfterCancel.itemId -eq $originalItemId -and $slotAfterCancel.modifierId -eq $originalModifierId)
        InvalidItemRejectedWithoutMutation = [bool]$invalidNoMutation
        InventoryClosedToMapAfterTests = ($afterCancel.data.returnedToMap -and $invalidCancel.data.returnedToMap -and $pauseEnd.status -eq 'completed')
        TimeModeUnchangedDuringStopTransactions = ($unequipDraft.data.timeControlModeBefore -eq 'Stop' -and $unequipDraft.data.timeControlModeAfter -eq 'Stop' -and $equipDraft.data.timeControlModeAfter -eq 'Stop')
        FormalFixtureUnchanged = ($fixtureHashBefore -eq $fixtureHashAfter)
        ProcessStopped = [bool]$stop.processStopped
    }
    $failedAssertions = @($assertions.Keys | Where-Object { -not [bool]$assertions[$_] })
    $result = [ordered]@{
        EquipmentMode = $mode
        SlotIndex = $slotIndex
        ItemId = $originalItemId
        ModifierId = $originalModifierId
        UnequipDraft = $unequipDraft.data
        UnequipCommit = $unequipCommit.data
        EquipDraft = $equipDraft.data
        EquipCommit = $equipCommit.data
        CancelDraft = $cancelDraft.data
        CancelReceipt = $cancel.data
        InvalidItemStatus = [string]$invalidItem.status
        Assertions = $assertions
        FailedAssertions = $failedAssertions
        FixtureHashBefore = $fixtureHashBefore
        FixtureHashAfter = $fixtureHashAfter
        ProcessStopped = [bool]$stop.processStopped
        Passed = ($failedAssertions.Count -eq 0)
    }
    $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 16
    if (-not $result.Passed) { throw 'Native MainHero Inventory equip/unequip/Done/Cancel transaction regression failed.' }
}
finally {
    if (Test-Path -LiteralPath $sessionPath) {
        try {
            $current = Get-State "cleanup-state-$([Guid]::NewGuid().ToString('N'))"
            if ($current.state.context.gameState -eq 'InventoryState') {
                $pending = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-cleanup-options")
                if ($pending.status -eq 'completed') { Invoke-AgentCli 'inventoryCancelChanges' @('-CommandId', "$commandPrefix-cleanup-cancel") | Out-Null }
            }
            Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup") 20 | Out-Null
        } catch { try { Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-cleanup-again") 20 | Out-Null } catch { } }
    }
    if ($null -eq $previousHarnessMode) { Remove-Item Env:CHRONICLE_HARNESS_MODE -ErrorAction SilentlyContinue }
    else { $env:CHRONICLE_HARNESS_MODE = $previousHarnessMode }
}
