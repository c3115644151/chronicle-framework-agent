# Proposal

## Why

Several Native AI-controller handoffs left MainHero stationary in Battle, and the user-confirmed F6 order controls troop formations only. Chronicle already has a short `MovementInputVector` lease for friendly Location Missions; a bounded zero-model test can establish whether the same player-like input path can move MainHero during a Campaign field battle.

## What Changes

- Add a Harness-only battle movement-input probe, guarded to an active ordinary Campaign field Battle Mission, Player-controlled MainAgent, and Campaign time Stop.
- Apply one short movement vector through the existing post-`MissionMainAgentController.ControlTick` input route, measure position/health, then clear it.
- Keep the production `missionInput` action location-only and keep the new probe out of AgentHost.

## Capabilities

### New Capabilities

None. This is an implementation feasibility check for the still-open [#132](https://github.com/c3115644151/chronicle-framework-agent/issues/132), not a player-facing feature.

### Modified Capabilities

None. The Native F6 contract and existing Location Mission input limits remain unchanged.

## Impact

Potentially touches `AgentMissionInputPatch`, Native protocol, CLI, and the existing disposable Battle Mission probe. It uses zero model calls, a hash-verified SaveAs clone, a maximum 0.5-second input vector, and no Campaign time action.
