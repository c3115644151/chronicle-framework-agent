# Proposal

## Why

Two bounded real-model continuations of the same natural StoryMode Campaign encountered the same 432-denar Tavern hiring quote; the player had 424, then 64. The Host chose the Native “cannot pay” answer and excluded that Hero only in memory for the current run. After a safe checkpoint and Host restart, that per-run exclusion was lost and the same Town/Hero dialogue was repeated, consuming another ¥0.10 continuation without advancing the Companion objective.

## What Changes

- Persist the exact Wanderer Hero ID and the player's Gold balance when the current Native hiring dialogue exposes its “cannot pay” response.
- While Gold has not risen above that recorded balance, omit only that Hero from Companion candidates; keep other current Wanderers and other Companion routes available.
- Reconsider that Hero after Gold rises, and retain the Native dialogue as the authority for whether hiring is currently available.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `companion-search-recovery`: persist a candidate-specific unaffordable observation independently from unrelated EYC Journal progress.

## Impact

The existing Campaign-bound Companion search checkpoint codec and `AgentHostEstablishClanCompanionLoop` candidate filtering/action handling. No new Native action, player-facing control, provider dependency, or model call is added. Parent GitHub issue: [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130).
