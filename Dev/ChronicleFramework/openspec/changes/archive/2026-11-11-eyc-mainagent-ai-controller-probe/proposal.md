# Proposal

## Why

F6 only gives the Native AI control of troop formations; the player-confirmed behavior is that MainHero does not act autonomously. The remaining #132 question is whether Bannerlord's separate MainAgent AI controller can temporarily provide combat behavior and then return control without breaking the battle or aftermath flow.

## What Changes

- Add an opt-in, no-model Native probe on a disposable ordinary Campaign field-battle clone.
- Temporarily switch the active MainAgent controller to Native AI for a bounded Mission-time lease, sample its controller, formation, position, health, and battle state, then restore Player control or restore automatically on timeout/Mission change.
- Keep the probe outside the production Agent action catalog and Host loop. Do not ship the controller handoff as a player capability unless Native evidence supports a separate product change.

## Capabilities

### New Capabilities

None. This is a temporary validation tool for the unresolved MainHero-safety acceptance already tracked by [#132](https://github.com/c3115644151/chronicle-framework-agent/issues/132); it introduces no player-facing behavior.

### Modified Capabilities

None. F6's existing contract remains that only troop formations are delegated and MainHero remains Agent-controlled.

## Impact

Potentially touches the native bridge, CLI, and opt-in battle probe script. Use only a hash-verified disposable campaign clone, keep Campaign time stopped, use zero model requests, and restore the MainAgent controller before leaving the Mission. The acceptance issue stays open until safe MainHero control and the parent EYC gate are proven.
