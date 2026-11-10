# Design

## Context

See `proposal.md` for the live trace. `AgentHostEstablishClanCompanionLoop` already tracks the selected Hero, start distance, and a two-attempt no-progress limit. The model-requested `missionSceneAgents` action applies `EvaluateNavigationNoProgress`, but after a Native `missionNavigateToAgent` the loop clears its scene receipt and performs the next scene query itself before prompting. That automatic branch omits the existing reconciliation logic, so the model repeatedly sees the same candidate.

## Goals / Non-Goals

**Goals:**

- Apply one shared navigation-progress reconciliation function to both automatic and explicitly requested Native scene observations.
- Keep a candidate eligible after measurable approach or when Native interaction is available; temporarily exclude it only after two completed, unproductive navigation attempts.
- When exclusion leaves no eligible Wanderer in the current scene, use the already-listed original Native `missionLeave` path.

**Non-Goals:**

- Add a new game action, send keyboard input, alter camera/Focus, relax `Agent.OnUse` gates, or teleport the MainAgent.
- Exclude all Tavern targets after one navigation or permanently across changed Campaign/Journal state.
- Change the two-campaign EYC acceptance gate.

## Decisions

- Factor the current post-navigation no-progress logic into one helper and call it immediately after both scene-observation paths receive a successful fresh Native roster.
- Reconcile before filtering candidates or building the next model request, so `excludedHeroes` is reflected in the current catalog rather than only in a later pass.
- Retain the existing threshold and retry count (two completed attempts below 0.1 distance improvement while Native conversation remains unavailable); do not increase model calls solely to diagnose navigation.
- Extend the package self-test to simulate one successful approach followed by two unchanged observations and verify the target is offered initially, then excluded with Leave still available.

## Risks / Trade-offs

- **A transient Native state could make an Agent appear non-interactable** → Keep the two-attempt threshold and require both a fresh scene distance and a fresh Native interaction result before exclusion.
- **The loop might forget to reset the counter when an Agent becomes usable** → The shared helper explicitly clears prior attempts when interaction becomes available.
- **The Agent may be excluded even though a later pose/timing change would help** → Exclusion lasts only for the current Town search; Native Leave returns to the map and other safe settlements remain available.
