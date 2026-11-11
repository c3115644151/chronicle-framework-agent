# Proposal

## Why

The first Native probe changed MainAgent.Controller to AI but observed no movement over 10 seconds. Installed 1.4.8 source shows Formation AI control executes its `ActiveBehavior` only when one exists, so the next measurement must establish whether MainHero's singleton formation has an actionable behavior during battle.

## What Changes

- Add read-only ActiveBehavior, current order, and target/distance to the existing battle status observation for MainAgent's current Formation.
- Compare standalone MainAgent AI control with a reversible Native handoff that temporarily makes a friendly soldier the Mission MainAgent, then refreshes the original MainHero formation's AI behavior.
- Record both variants in the existing opt-in zero-model probe on one hash-verified disposable Campaign clone. No gameplay action or Host behavior is added.

## Capabilities

### New Capabilities

None. This is a test observation for the unresolved control/safety acceptance in [#132](https://github.com/c3115644151/chronicle-framework-agent/issues/132).

### Modified Capabilities

None. The production contract remains that F6 controls troop formations and leaves MainHero player-controlled.

## Impact

Touches only the Native status observer and existing opt-in probe. The test uses no model calls or explicit Campaign clock action, deletes only its hash-verified disposable SaveAs clone, and leaves the source save unchanged.
