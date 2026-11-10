# Proposal

## Why

The bounded production run `TestResults/20261110-172629` resumed the saved Companion objective, reached the Tavern, and then issued nine navigation decisions for the same Wanderer; observed distance flattened near 1.363 while Native interaction stayed unavailable. Source review found the existing two-attempt stall breaker only runs when the model explicitly asks for `missionSceneAgents`, but the production Host scans the scene automatically after navigation and bypasses that branch. This pays repeated model requests and leaves the candidate stuck in the catalog.

## What Changes

- Reconcile approach distance and Native interaction eligibility after every fresh scene scan, whether it is automatic or model-requested.
- Keep the existing measured-progress threshold and two-consecutive-no-progress limit.
- Exclude a stalled candidate from the current Tavern decision catalog and use other current candidates or the original Native Leave path.
- Preserve current Native action permission checks; do not add a direct conversation or teleport action.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `companion-search-recovery`: apply the existing navigation-stall recovery contract to the automatic production scene-observation path.

## Impact

AgentHost's Companion subgoal and deterministic package regression tests, plus the existing stable Companion search/recovery specification. This is a focused implementation correction under GitHub Issue [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130); no parallel issue is created.
