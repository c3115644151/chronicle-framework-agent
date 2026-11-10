# Proposal

## Why

The same bounded natural EYC run spent several model calls on repeated `observeAgain` choices while the Native MainParty was already moving toward one visible hostile Party. In `TestResults/20261110-220446`, 3 such waiting decisions were followed by an Encounter; each call added model cost but chose no new world action. Earlier same-branch runs showed the same pattern at larger counts.

## What Changes

- After the model chooses a current Native `pursue` action, use a bounded Host-side monitor to observe the already-running Native pursuit.
- Poll only current Native state/visible Party targets; return to the model when an encounter, conversation, incident, target loss, stop, or bounded-window expiry occurs.
- Keep all world-time changes under the existing Native time mode; the monitor must not send Pause, Resume, Advance, or FastForward.

## Capabilities

### New Capabilities

- `native-party-pursuit-monitor`: passively observe a selected Native party pursuit until a meaningful state boundary.

### Modified Capabilities

None.

## Impact

The Host's existing BattleSimulation pursuit loop and Native map-movement monitor; no new gameplay ACT, button, or dependency. Parent product issue: [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130).
