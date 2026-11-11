# Proposal

## Why

The current battle probes changed MainAgent's controller and a few state flags, but the installed RTS Camera 5.4.16 handoff also initializes the Native AI components, adjusts AI flags, clears scripted movement, unpauses the Agent, refreshes its formation order, and changes the MainAgent controller-view state. The partial probes therefore do not establish whether the complete source-backed handoff can move MainHero in this 1.4.8 field-battle setup.

## What Changes

- Add one bounded, Harness-only, zero-model probe of the fuller Native MainAgent AI handoff on a disposable StoryMode field-battle clone.
- Record MainHero movement, health, Native battle aftermath, Campaign clock, restoration, source/clone hashes, and process cleanup.
- Keep the probe out of AgentHost and do not make a product safety claim from one battle.

## Capabilities

### New Capabilities

None. This is a scoped feasibility test for [#132](https://github.com/c3115644151/chronicle-framework-agent/issues/132), not a player-facing behavior change.

### Modified Capabilities

None. `skip_specs: true` is set because this change adds no product requirement.

## Impact

Harness Native bridge and battle probe script; Research/G and MAINLINE evidence; issue #132. No AgentHost action catalog, Campaign save, game rule, or external mod dependency changes.
