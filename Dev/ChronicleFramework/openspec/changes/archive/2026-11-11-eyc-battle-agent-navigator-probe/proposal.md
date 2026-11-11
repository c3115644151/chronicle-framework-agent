# Proposal

## Why

The zero-model battle movement pulse proves the current Native input vector can move MainHero a short distance, but it is not a practical long-duration navigation loop. Installed 1.4.8 `SandBox.AgentNavigator` already provides NavMesh path movement used for scene Agents; one bounded battle probe can establish whether this existing Native helper can move MainHero toward a safe point while troops are delegated.

## What Changes

- Add an opt-in Harness-only battle navigation lease that assigns a target point away from the nearest current enemy and observes the Native AgentNavigator result.
- Use no model calls and no explicit Campaign clock actions; restore MainHero's original Player controller on arrival, timeout, Mission change/end, or stop.
- Keep the action out of AgentHost and product action catalog until this probe and the pending battle-risk decision support a player-facing design.

## Capabilities

### New Capabilities

None. This is a feasibility check for existing issue [#132](https://github.com/c3115644151/chronicle-framework-agent/issues/132).

### Modified Capabilities

None. The existing Location-Mission Navigator and F6 contracts are not widened by this probe.

## Impact

Potentially touches Native bridge, CLI, and the existing disposable Battle Mission probe. The operation is restricted to a stopped ordinary field Battle Mission, one visible enemy-relative destination, a short lease, and a hash-verified SaveAs clone.
