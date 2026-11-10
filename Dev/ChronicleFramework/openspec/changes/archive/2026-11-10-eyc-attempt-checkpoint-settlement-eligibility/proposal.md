# Proposal

## Why

`TestResults/20261107-103723` resumed the hash-verified `freshB` save at the original Sargot Backstreet menu, but the production Host asked the model to select the Companion objective again before reading its saved pending attempt. The save Harness already treats that menu as checkpointable when its current Native Leave action is enabled and the settlement is not besieged, while the EYC attempt-memory gate rejected every `encounterActive` state. Aligning those two boundaries removes a real redundant paid decision and makes the restart contract hold for an actual saved Campaign.

## What Changes

- Permit objective-attempt checkpoint reads/writes from the same verified safe Native settlement menus accepted by the persistent-save Harness.
- Continue rejecting hostile Party encounters, sieged settlements, modal screens and Backstreet menus without an enabled Native Leave action.
- Add a production Host contract test that resumes a pending objective from a Town Backstreet checkpoint without calling the objective-selection provider.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `eyc-objective-continuation-memory`: include verified settlement menus among safe Campaign MapState checkpoints for pending attempt continuation.

## Impact

AgentHost EYC checkpoint eligibility, its deterministic Native/Provider contract tests, OpenSpec stable behavior specification, and the existing long-campaign Harness. This remains inside GitHub Issue [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130); no new product issue or vanilla gameplay action is introduced.
