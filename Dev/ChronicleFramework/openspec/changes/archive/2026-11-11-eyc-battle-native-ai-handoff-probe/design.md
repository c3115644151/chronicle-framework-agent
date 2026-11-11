# Design

## Context

See `proposal.md` for the reason. Installed source examined locally is Bannerlord 1.4.8 plus RTS Camera 5.4.16. `MissionSharedLibrary.Utilities.Utility.AIControlMainAgent` does more than set `Agent.Controller`: it clears interaction focus, initializes the MainAgent's CommonAI/HumanAI components, handles AI flags and mounted state, unpauses the Agent, clears scripted movement, refreshes its formation/order state, and may set its watch state. RTS Camera's free-camera path also disables `MissionMainAgentController` while the AI controls the Agent.

The earlier `TestResults/20261111-105107` only changed Controller, watch state, the player-in-formation flag, and order membership; it did not reproduce that full initialization. `TestResults/20261111-121911` assigned a point to `SandBox.AgentNavigator` but likewise did not initialize MainAgent AI. These are valid observations for those exact setups, not a test of the installed mod's complete AI handoff.

## Goals / Non-Goals

**Goals:**

- Test the source-backed AI handoff steps in one ordinary Campaign field Battle Mission.
- Capture MainHero position, health, formation/order state, Campaign clock, and final Native battle result.
- Restore Player control and saved controller/formation state on timeout, cancellation, Mission change/end, or process stop.

**Non-Goals:**

- No RTSCamera runtime dependency, new AgentHost action, LLM call, camera feature, or product behavior.
- No manipulation of battle outcome, damage, roster, renown, party size, or clock.
- No claim of safe combat from one battle.

## Decisions

1. **Reproduce Native AI setup locally in Harness code rather than load RTSCamera at runtime.** This avoids making the mod or test dependent on a third-party DLL while testing the exact operations identified in its current installed source. Camera movement is omitted because the hypothesis is whether initialized Native MainAgent AI can act; the Host still observes the same Mission.
2. **Bound and isolate the lease.** Use the current stopped Campaign field Battle, live Player-controlled MainAgent, a hash-verified disposable clone, and a maximum 180-second lease. Observe until the Native battle ends or the lease expires; restore state before the test exits.
3. **Interpret protocol pass separately from movement.** Build/Docs and the phase pass condition cover command guards, samples, restoration, unchanged source, clone removal, and process exit. Only position samples determine whether the tested AI setup moved MainHero.

## Risks / Trade-offs

- AI component initialization or formation refresh may have side effects beyond controller state → run only on a disposable clone and terminate cleanly.
- A short test can miss context-dependent AI behavior → report the exact sample and do not generalize to all battle modes.
- The installed reference includes camera behavior not reproduced here → this probe tests its Native MainAgent handoff operations, not full RTSCamera free-camera UX.

## Migration Plan

No migration. The Harness-only probe can be removed without changing saves or AgentHost behavior.

## Open Questions

None for this single feasibility probe.
