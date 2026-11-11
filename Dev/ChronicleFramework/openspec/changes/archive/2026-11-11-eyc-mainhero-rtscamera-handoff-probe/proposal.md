# Proposal

## Why

Installed 1.4.8 testing found that setting `Agent.Controller=AI` and re-notifying Formation movement did not move MainHero. A public RTSCamera repository describes a free-camera handoff that also changes watch state and a private formation flag, so a bounded local check is needed before ruling on that route.

## What Changes

- Add an opt-in, zero-model Harness-only operation that applies the current-version subset of the RTSCamera handoff in an ordinary Campaign field Battle Mission.
- Restore MainHero's controller, watch state, and formation flag on timeout, mission end, stop, or explicit cleanup.
- Record movement, health, order state, Campaign time, Native outcome, source hash, clone cleanup, and process cleanup. Do not add the operation to AgentHost.

## Capabilities

### New Capabilities

None. This is a diagnostic for the unresolved Battle Mission acceptance in [#132](https://github.com/c3115644151/chronicle-framework-agent/issues/132), not a player feature.

### Modified Capabilities

None. The existing F6 contract remains troop-formation delegation only.

## Impact

The bridge uses installed 1.4.8 Controller, WatchState, Formation, and MovementOrder APIs in a disposable SaveAs clone. No model calls, save mutation, roster edits, or Campaign clock changes are permitted.
