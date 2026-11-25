#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$LoadSaveName = 'AgentBridgeLifecycle',
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$HarnessPowerShell = Join-Path $PSHOME 'pwsh.exe'
$cli = Join-Path $PSScriptRoot 'Agent-Cli.ps1'
$savePath = Join-Path $env:USERPROFILE "Documents\Mount and Blade II Bannerlord\Game Saves\$LoadSaveName.sav"
$sessionPath = Join-Path $env:USERPROFILE 'Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent\session.json'
$resultPath = if ($env:CHRONICLE_HARNESS_TEMP) { Join-Path $env:CHRONICLE_HARNESS_TEMP 'EquipmentTransactionResult.json' } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults\ManualEquipmentTransactions\EquipmentTransactionResult.json' }
$previousHarnessMode = $env:CHRONICLE_HARNESS_MODE
$commandPrefix = 'equipment-' + (Get-Date -Format 'yyyyMMddHHmmssfff')

if (-not (Test-Path -LiteralPath $savePath)) { throw "Equipment transaction fixture not found: $LoadSaveName" }
if (Get-Process -Name Bannerlord -ErrorAction SilentlyContinue) { throw 'Bannerlord is already running.' }
$fixtureHashBefore = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash

function Invoke-AgentCli([string]$Action, [string[]]$Arguments = @(), [int]$CommandTimeout = 0) {
    $effectiveTimeout = if ($CommandTimeout -gt 0) { $CommandTimeout } else { $TimeoutSeconds }
    $output = & $HarnessPowerShell -NoProfile -File $cli $Action @Arguments -TimeoutSeconds $effectiveTimeout -AsJson 2>&1 | Out-String
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
    $modifierFixtureSeed = Invoke-AgentCli 'harnessSeedEquipmentModifierFixture' @('-CommandId', "$commandPrefix-modifier-fixture-seed")
    if ($modifierFixtureSeed.status -ne 'completed' -or [int]$modifierFixtureSeed.data.countAfter -ne 1)
        { throw 'The Harness could not add its exact masterwork EquipmentElement fixture to the disposable Campaign.' }

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

    $swapSourceInventory = Open-Inventory 'swap-source'
    $swapSourceSlot = @($swapSourceInventory.Options.data.equipmentSlots | Where-Object {
        [int]$_.equipmentIndex -ne $slotIndex -and -not [string]::IsNullOrWhiteSpace([string]$_.itemId)
    } | Select-Object -First 1)
    if ($swapSourceSlot.Count -ne 1) { throw 'Native SPInventoryVM exposes no second occupied slot for the equipment exchange fixture.' }
    $swapSourceIndex = [int]$swapSourceSlot[0].equipmentIndex
    $swapSourceItemId = [string]$swapSourceSlot[0].itemId
    $swapSourceModifierId = [string]$swapSourceSlot[0].modifierId
    $swapSourceDraft = Invoke-AgentCli 'unequipHeroItem' @('-EquipmentIndex', [string]$swapSourceIndex, '-CommandId', "$commandPrefix-swap-source-draft")
    $swapSourceCommit = Invoke-AgentCli 'inventoryConfirm' @('-CommandId', "$commandPrefix-swap-source-confirm")
    if ($swapSourceDraft.status -ne 'completed' -or -not $swapSourceDraft.data.draftCreatedByNativeVM -or -not $swapSourceCommit.data.postconditionPassed)
        { throw 'Could not place a second native EquipmentElement in PlayerInventory for the exchange fixture.' }

    $swapInventory = Open-Inventory 'swap-target'
    $replacementItem = Find-InventoryElement $swapInventory.Options $swapSourceItemId $swapSourceModifierId
    $modifierVariantCandidate = Find-InventoryElement $swapInventory.Options $swapSourceItemId 'masterwork_sword'
    $modifierVariantIdsDistinct = (
        $null -ne $replacementItem -and $null -ne $modifierVariantCandidate -and
        [string]$replacementItem.viewModelItemId -ne [string]$modifierVariantCandidate.viewModelItemId
    )
    if (-not $modifierVariantIdsDistinct)
        { throw 'Native SPInventoryVM did not provide distinct current Item VM identities for the same ItemObject with different modifiers.' }
    if ($null -eq $replacementItem -or [string]::IsNullOrWhiteSpace([string]$replacementItem.viewModelItemId))
        { throw 'The second native EquipmentElement was not available as an exchange candidate.' }
    $swapDraft = Invoke-AgentCli 'equipHeroItem' @('-ItemViewModelId', [string]$replacementItem.viewModelItemId, '-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-swap-draft")
    $swapDraftOptions = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-swap-preview")
    $swapTargetPreview = Find-EquipmentSlot $swapDraftOptions $slotIndex
    $displacedItemPreview = Find-InventoryElement $swapDraftOptions $originalItemId $originalModifierId
    $swapDraftPassed = (
        $swapDraft.status -eq 'completed' -and [bool]$swapDraft.data.draftCreatedByNativeVM -and
        [string]$swapTargetPreview.itemId -eq $swapSourceItemId -and [string]$swapTargetPreview.modifierId -eq $swapSourceModifierId -and
        $null -ne $displacedItemPreview
    )
    if (-not $swapDraftPassed) { throw 'Native SPInventoryVM did not preview both sides of the occupied-slot equipment exchange.' }
    $swapCommit = Invoke-AgentCli 'inventoryConfirm' @('-CommandId', "$commandPrefix-swap-confirm")
    if ($swapCommit.status -ne 'completed' -or -not $swapCommit.data.postconditionPassed)
        { throw 'Native Done did not commit the occupied-slot equipment exchange.' }

    $reverseInventory = Open-Inventory 'swap-reverse'
    $displacedItem = Find-InventoryElement $reverseInventory.Options $originalItemId $originalModifierId
    if ($null -eq $displacedItem) { throw 'The prior equipment was not returned to PlayerInventory by Native Done.' }
    $reverseDraft = Invoke-AgentCli 'equipHeroItem' @('-ItemViewModelId', [string]$displacedItem.viewModelItemId, '-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-swap-reverse-draft")
    $reverseCommit = Invoke-AgentCli 'inventoryConfirm' @('-CommandId', "$commandPrefix-swap-reverse-confirm")
    if ($reverseDraft.status -ne 'completed' -or -not $reverseCommit.data.postconditionPassed)
        { throw 'Could not restore the original MainHero equipment after the exchange fixture.' }

    $restoreInventory = Open-Inventory 'swap-restore'
    $replacementToRestore = Find-InventoryElement $restoreInventory.Options $swapSourceItemId $swapSourceModifierId
    if ($null -eq $replacementToRestore) { throw 'The replacement EquipmentElement was not available to restore its original slot.' }
    $restoreDraft = Invoke-AgentCli 'equipHeroItem' @('-ItemViewModelId', [string]$replacementToRestore.viewModelItemId, '-EquipmentIndex', [string]$swapSourceIndex, '-CommandId', "$commandPrefix-swap-restore-draft")
    $restoreCommit = Invoke-AgentCli 'inventoryConfirm' @('-CommandId', "$commandPrefix-swap-restore-confirm")
    if ($restoreDraft.status -ne 'completed' -or -not $restoreCommit.data.postconditionPassed)
        { throw 'Could not restore the second MainHero equipment slot after the exchange fixture.' }
    $restoredInventory = Open-Inventory 'swap-restored'
    $restoredOriginalSlot = Find-EquipmentSlot $restoredInventory.Options $slotIndex
    $restoredSecondSlot = Find-EquipmentSlot $restoredInventory.Options $swapSourceIndex
    $initialSlotSnapshot = @($opened.Options.data.equipmentSlots | Select-Object slotName,equipmentIndex,itemId,modifierId | ConvertTo-Json -Depth 4 -Compress)
    $restoredSlotSnapshot = @($restoredInventory.Options.data.equipmentSlots | Select-Object slotName,equipmentIndex,itemId,modifierId | ConvertTo-Json -Depth 4 -Compress)
    $allEquipmentRestored = (($initialSlotSnapshot -join '') -ceq ($restoredSlotSnapshot -join ''))
    $exchangeRestored = (
        [string]$restoredOriginalSlot.itemId -eq $originalItemId -and [string]$restoredOriginalSlot.modifierId -eq $originalModifierId -and
        [string]$restoredSecondSlot.itemId -eq $swapSourceItemId -and [string]$restoredSecondSlot.modifierId -eq $swapSourceModifierId
    )
    $restoreClose = Invoke-AgentCli 'inventoryCancel' @('-CommandId', "$commandPrefix-swap-restored-close")

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
    $staleBefore = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-stale-before")
    $staleInventoryBefore = @($staleBefore.data.rightItems | Select-Object viewModelItemId,itemId,modifierId,inventorySide,itemCount | ConvertTo-Json -Depth 4 -Compress) -join ''
    $staleItem = Invoke-AgentCli 'equipHeroItem' @('-ItemViewModelId', [string]$replacementItem.viewModelItemId, '-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-stale-item")
    $staleAfter = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-stale-after")
    $staleOriginalSlot = Find-EquipmentSlot $staleAfter $slotIndex
    $staleSecondSlot = Find-EquipmentSlot $staleAfter $swapSourceIndex
    $staleInventoryAfter = @($staleAfter.data.rightItems | Select-Object viewModelItemId,itemId,modifierId,inventorySide,itemCount | ConvertTo-Json -Depth 4 -Compress) -join ''
    $staleNoMutation = (
        $staleItem.status -eq 'rejected' -and
        [string]$staleOriginalSlot.itemId -eq $originalItemId -and [string]$staleOriginalSlot.modifierId -eq $originalModifierId -and
        [string]$staleSecondSlot.itemId -eq $swapSourceItemId -and [string]$staleSecondSlot.modifierId -eq $swapSourceModifierId -and
        $staleInventoryBefore -ceq $staleInventoryAfter
    )
    $invalidItem = Invoke-AgentCli 'equipHeroItem' @('-ItemViewModelId', 'chronicle_invalid_item_vm_id', '-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-invalid-item")
    $invalidAfter = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-invalid-after")
    $invalidSlotItem = @($invalidAfter.data.equipmentSlots | Where-Object { [int]$_.equipmentIndex -eq $slotIndex } | Select-Object -First 1)[0]
    $invalidNoMutation = ($invalidItem.status -eq 'rejected' -and [string]$invalidSlotItem.itemId -eq $originalItemId -and [string]$invalidSlotItem.modifierId -eq $originalModifierId)
    $invalidCancel = Invoke-AgentCli 'inventoryCancel' @('-CommandId', "$commandPrefix-close-invalid")

    $qualityInventory = Open-Inventory 'quality-equip'
    $masterworkCandidate = Find-InventoryElement $qualityInventory.Options 'vlandia_sword_1_t2' 'masterwork_sword'
    if ($null -eq $masterworkCandidate -or [string]::IsNullOrWhiteSpace([string]$masterworkCandidate.viewModelItemId))
        { throw 'The Native Inventory VM did not expose the seeded masterwork sword as a distinct EquipmentElement candidate.' }
    $incompatibleSlot = @($qualityInventory.Options.data.equipmentSlots | Where-Object { $_.slotName -eq 'CharacterTorsoSlot' } | Select-Object -First 1)
    if ($incompatibleSlot.Count -ne 1) { throw 'Native SPInventoryVM did not expose the current MainHero torso slot for the incompatible-item guard.' }
    $incompatibleSlotItem = Invoke-AgentCli 'equipHeroItem' @('-ItemViewModelId', [string]$masterworkCandidate.viewModelItemId, '-EquipmentIndex', [string]$incompatibleSlot[0].equipmentIndex, '-CommandId', "$commandPrefix-incompatible-slot")
    $incompatibleSlotAfter = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-incompatible-slot-after")
    $incompatibleTorsoAfter = Find-EquipmentSlot $incompatibleSlotAfter ([int]$incompatibleSlot[0].equipmentIndex)
    $masterworkStillInInventory = Find-InventoryElement $incompatibleSlotAfter 'vlandia_sword_1_t2' 'masterwork_sword'
    $incompatibleSlotNoMutation = (
        $incompatibleSlotItem.status -eq 'rejected' -and
        [string]$incompatibleTorsoAfter.itemId -eq [string]$incompatibleSlot[0].itemId -and
        [string]$incompatibleTorsoAfter.modifierId -eq [string]$incompatibleSlot[0].modifierId -and
        $null -ne $masterworkStillInInventory
    )
    if (-not $incompatibleSlotNoMutation) { throw 'Native SPInventoryVM did not reject the incompatible masterwork sword/torso slot pair without mutation.' }
    $masterworkCandidate = $masterworkStillInInventory
    $qualityDraft = Invoke-AgentCli 'equipHeroItem' @('-ItemViewModelId', [string]$masterworkCandidate.viewModelItemId, '-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-quality-draft")
    $qualityPreview = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-quality-preview")
    $qualityDraftSlot = Find-EquipmentSlot $qualityPreview $slotIndex
    $qualityDraftPassed = (
        $qualityDraft.status -eq 'completed' -and [bool]$qualityDraft.data.draftCreatedByNativeVM -and
        [string]$qualityDraftSlot.itemId -eq 'vlandia_sword_1_t2' -and [string]$qualityDraftSlot.modifierId -eq 'masterwork_sword'
    )
    if (-not $qualityDraftPassed) { throw 'The Native SPInventoryVM did not retain the non-empty item modifier in its equipment draft.' }
    $qualityCommit = Invoke-AgentCli 'inventoryConfirm' @('-CommandId', "$commandPrefix-quality-confirm")
    if (-not $qualityCommit.data.postconditionPassed) { throw 'Native Done did not commit the exact modified EquipmentElement.' }
    $qualityAfterCommit = Open-Inventory 'quality-after-commit'
    $qualityCommittedSlot = Find-EquipmentSlot $qualityAfterCommit.Options $slotIndex
    $qualityCommitted = ([string]$qualityCommittedSlot.itemId -eq 'vlandia_sword_1_t2' -and [string]$qualityCommittedSlot.modifierId -eq 'masterwork_sword')
    if (-not $qualityCommitted) { throw 'The committed native Equipment lost or changed its masterwork modifier.' }
    $qualityUnequip = Invoke-AgentCli 'unequipHeroItem' @('-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-quality-unequip")
    $qualityUnequipPreview = Invoke-AgentCli 'heroEquipmentOptions' @('-CommandId', "$commandPrefix-quality-unequip-preview")
    $qualityInInventoryPreview = Find-InventoryElement $qualityUnequipPreview 'vlandia_sword_1_t2' 'masterwork_sword'
    $qualityUnequipPassed = ($qualityUnequip.status -eq 'completed' -and [bool]$qualityUnequip.data.draftCreatedByNativeVM -and $null -ne $qualityInInventoryPreview)
    if (-not $qualityUnequipPassed) { throw 'Native SPInventoryVM unequip did not preserve the modified EquipmentElement in its draft inventory.' }
    $qualityUnequipCommit = Invoke-AgentCli 'inventoryConfirm' @('-CommandId', "$commandPrefix-quality-unequip-confirm")
    if (-not $qualityUnequipCommit.data.postconditionPassed) { throw 'Native Done did not return the exact modified EquipmentElement to Party inventory.' }
    $qualityRestoreInventory = Open-Inventory 'quality-restore-shield'
    $qualityMasterworkAfterUnequip = Find-InventoryElement $qualityRestoreInventory.Options 'vlandia_sword_1_t2' 'masterwork_sword'
    $shieldAfterQuality = Find-InventoryElement $qualityRestoreInventory.Options $originalItemId $originalModifierId
    if ($null -eq $qualityMasterworkAfterUnequip -or $null -eq $shieldAfterQuality)
        { throw 'Native inventory did not retain both the modifier fixture and the displaced shield after unequip.' }
    $shieldRestoreDraft = Invoke-AgentCli 'equipHeroItem' @('-ItemViewModelId', [string]$shieldAfterQuality.viewModelItemId, '-EquipmentIndex', [string]$slotIndex, '-CommandId', "$commandPrefix-quality-restore-shield-draft")
    $shieldRestoreCommit = Invoke-AgentCli 'inventoryConfirm' @('-CommandId', "$commandPrefix-quality-restore-shield-confirm")
    if ($shieldRestoreDraft.status -ne 'completed' -or -not $shieldRestoreCommit.data.postconditionPassed)
        { throw 'Could not restore the original shield after the modifier round trip.' }
    $qualityRestoreOptions = Open-Inventory 'quality-restored'
    $qualityRestoredSlot = Find-EquipmentSlot $qualityRestoreOptions.Options $slotIndex
    $qualityRestoredCandidate = Find-InventoryElement $qualityRestoreOptions.Options 'vlandia_sword_1_t2' 'masterwork_sword'
    $qualityRestored = ([string]$qualityRestoredSlot.itemId -eq $originalItemId -and [string]$qualityRestoredSlot.modifierId -eq $originalModifierId -and $null -ne $qualityRestoredCandidate)
    $qualityClose = Invoke-AgentCli 'inventoryCancel' @('-CommandId', "$commandPrefix-quality-close")
    $modifierFixtureCleanup = Invoke-AgentCli 'harnessClearEquipmentModifierFixture' @('-CommandId', "$commandPrefix-modifier-fixture-clear")
    if ($modifierFixtureCleanup.status -ne 'completed' -or [int]$modifierFixtureCleanup.data.countAfter -ne 0)
        { throw 'The test-only masterwork EquipmentElement was not removed from the disposable MainParty inventory.' }

    $pauseEnd = Invoke-AgentCli 'pause' @('-CommandId', "$commandPrefix-pause-end")
    $mapAfterTransactions = Get-State 'map-after-transactions'
    $stop = Invoke-AgentCli 'stop' @('-CommandId', "$commandPrefix-stop") 30
    $fixtureHashAfter = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $partyStateUnchanged = (
        $mapAfterTransactions.state.party.members -eq $mapBefore.state.party.members -and
        $mapAfterTransactions.state.party.healthy -eq $mapBefore.state.party.healthy -and
        $mapAfterTransactions.state.party.wounded -eq $mapBefore.state.party.wounded -and
        $mapAfterTransactions.state.party.prisoners -eq $mapBefore.state.party.prisoners -and
        $mapAfterTransactions.state.party.sizeLimit -eq $mapBefore.state.party.sizeLimit -and
        $mapAfterTransactions.state.party.itemCount -eq $mapBefore.state.party.itemCount -and
        $mapAfterTransactions.state.party.cargoWeight -eq $mapBefore.state.party.cargoWeight -and
        $mapAfterTransactions.state.party.morale -eq $mapBefore.state.party.morale -and
        $mapAfterTransactions.state.party.food -eq $mapBefore.state.party.food -and
        $mapAfterTransactions.state.party.dailyWage -eq $mapBefore.state.party.dailyWage
    )
    $campaignAndLocationUnchanged = (
        $mapAfterTransactions.state.context.gameState -eq 'MapState' -and
        $mapAfterTransactions.state.context.timeControlMode -eq 'Stop' -and
        [double]$mapAfterTransactions.state.campaignDay -eq [double]$mapBefore.state.campaignDay -and
        $mapAfterTransactions.state.economy.gold -eq $mapBefore.state.economy.gold -and
        $mapAfterTransactions.state.economy.influence -eq $mapBefore.state.economy.influence -and
        $mapAfterTransactions.state.economy.renown -eq $mapBefore.state.economy.renown -and
        [double]$mapAfterTransactions.state.location.x -eq [double]$mapBefore.state.location.x -and
        [double]$mapAfterTransactions.state.location.y -eq [double]$mapBefore.state.location.y -and
        $mapAfterTransactions.state.location.currentSettlementId -eq $mapBefore.state.location.currentSettlementId -and
        $mapAfterTransactions.state.location.targetSettlementId -eq $mapBefore.state.location.targetSettlementId -and
        $mapAfterTransactions.state.location.targetPartyId -eq $mapBefore.state.location.targetPartyId
    )
    $assertions = [ordered]@{
        OriginalEntryOpenedNativeInventoryState = [bool]$opened.Open.data.inventoryStateActive
        MainHeroEquipmentReadFromNativeVM = [bool]$opened.Options.data.isMainHeroSelected
        NativeUnequipTransferDraftMatchesState = [bool]$unequipDraftPassed
        NativeDoneCommittedUnequip = ([bool]$unequipCommit.data.committed -and [bool]$unequipCommit.data.postconditionPassed)
        NativeEquipTransferDraftMatchesState = [bool]$equipDraftPassed
        NativeDoneCommittedEquip = ([bool]$equipCommit.data.committed -and [bool]$equipCommit.data.postconditionPassed)
        NativeOccupiedSlotExchangeMatchesVM = [bool]$swapDraftPassed
        SameBaseItemVariantsHaveDistinctCurrentVMIds = [bool]$modifierVariantIdsDistinct
        NativeDoneCommittedOccupiedSlotExchange = [bool]$swapCommit.data.postconditionPassed
        ExchangeFixtureRestoredOriginalSlots = [bool]$exchangeRestored
        AllEquipmentSlotsRestored = [bool]$allEquipmentRestored
        NativeCancelConfirmationDiscardedDraft = ($cancel.data.discardConfirmed -and $slotAfterCancel.itemId -eq $originalItemId -and $slotAfterCancel.modifierId -eq $originalModifierId)
        StaleNativeItemCandidateRejectedWithoutMutation = [bool]$staleNoMutation
        InvalidItemRejectedWithoutMutation = [bool]$invalidNoMutation
        IncompatibleNativeItemSlotRejectedWithoutMutation = [bool]$incompatibleSlotNoMutation
        NonEmptyModifierSurvivesEquipDoneUnequipDone = ([bool]$qualityDraftPassed -and [bool]$qualityCommitted -and [bool]$qualityUnequipPassed -and [bool]$qualityRestored)
        ModifierFixtureRemovedBeforeCampaignStateComparison = ([int]$modifierFixtureCleanup.data.countAfter -eq 0)
        InventoryClosedToMapAfterTests = ($restoreClose.data.returnedToMap -and $afterCancel.data.returnedToMap -and $invalidCancel.data.returnedToMap -and $qualityClose.data.returnedToMap -and $pauseEnd.status -eq 'completed')
        TimeModeUnchangedDuringStopTransactions = ($unequipDraft.data.timeControlModeBefore -eq 'Stop' -and $unequipDraft.data.timeControlModeAfter -eq 'Stop' -and $equipDraft.data.timeControlModeAfter -eq 'Stop')
        PartyStateUnchanged = [bool]$partyStateUnchanged
        GoldInfluenceRenownLocationAndTimeUnchanged = [bool]$campaignAndLocationUnchanged
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
        Exchange = [ordered]@{ SourceSlotIndex = $swapSourceIndex; SourceItemId = $swapSourceItemId; SourceModifierId = $swapSourceModifierId; ModifierVariantViewModelId = $modifierVariantCandidate.viewModelItemId; Draft = $swapDraft.data; Commit = $swapCommit.data; Restored = $exchangeRestored }
        ModifierRoundTrip = [ordered]@{ Seed = $modifierFixtureSeed.data; EquipDraft = $qualityDraft.data; EquipCommit = $qualityCommit.data; CommittedSlot = $qualityCommittedSlot; UnequipDraft = $qualityUnequip.data; UnequipCommit = $qualityUnequipCommit.data; RestoredSlot = $qualityRestoredSlot; CandidateAfterUnequip = $qualityMasterworkAfterUnequip; Cleanup = $modifierFixtureCleanup.data }
        IncompatibleSlotStatus = [string]$incompatibleSlotItem.status
        CancelDraft = $cancelDraft.data
        CancelReceipt = $cancel.data
        StaleItemStatus = [string]$staleItem.status
        InvalidItemStatus = [string]$invalidItem.status
        PostTransactionCampaignState = $mapAfterTransactions.state
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
