# Design

## Context

The EYC parent already rereads the original Journal after each route, and it keeps an in-memory `unavailableObjectives` set plus a Native route fingerprint. Both are created inside one `AgentHostEstablishYourClanAutonomyLoop.RunAsync`; a new Host gets empty collections. `BuildObjectiveRouteAvailabilityFingerprint` already ignores time-only movement while including the current menu/location/targets, MainParty/economy/captivity, and nearby parties. The Campaign checkpoint codec preserves Chronicle-owned JSON fields and binds the payload to the current Campaign instance.

Real evidence shows why restart continuity matters: `TestResults/20261107-080214` reached Native `recruitOptions` and was stopped by the ¥0.30 reservation before troop selection. `TestResults/20261107-081552` restarted from the same safe Town checkpoint; with 8 decisions/¥0.10, the model selected Companion again, entered a Bandit encounter, and stopped before a safe checkpoint. Actual spend was ¥0.037412352, no objective advanced, and the prior save remained authoritative. This proves route selection is lost across these Host restarts. It does not establish that the uninterrupted production Host repeats the same plan.

## Goals / Non-Goals

**Goals:**

- Resume a model-selected objective after a budget-limited safe restart without asking the model to classify/reselect the same subgoal when its Journal and Native route state are unchanged.
- Preserve a no-progress route outcome across restart and avoid offering that route again until its Native availability fingerprint or Journal changes.
- Re-read the current Native UI/action catalog before any gameplay decision; persist only bounded structured facts in the existing save checkpoint.

**Non-Goals:**

- Hardcode a universal order among Gold, PartySize, Renown, and Companion.
- Resume a stale Native action, replay model output, or treat a query result as a gameplay action.
- Save objective-attempt memory from an unsafe Encounter/Mission/modal state.
- Change the original Quest, Campaign clock, battle, recruitment, ransom, or other Native mechanics.

## Decisions

1. **Reuse the Campaign-scoped Native checkpoint.** Add optional property `eycObjectiveAttemptMemoryV1`; keep at most one compact entry for each of the four current EYC objective IDs. Store outcome class (`pending`/`blocked`), termination code, original Journal before/after snapshots, and the current route fingerprint. Do not store prompts, completion text, raw provider output, or secrets.
2. **Separate budget-pending from gameplay-blocked.** If the provider/budget stopped before a Native choice, persist `pending`; when the same Campaign restarts with unchanged Journal/fingerprint, skip the read-only objective-selection call and resume that objective executor after fresh Native observation. If a verified subflow ends without Journal progress because its Native route is unavailable, persist `blocked`; when the same route fingerprint returns, omit it from the planner catalog but leave other supported unmet objectives selectable.
3. **Use current Native facts to reopen routes.** If the original Journal changes or `BuildObjectiveRouteAvailabilityFingerprint` differs, clear that objective's old entry and restore it to the current catalog. The fingerprint is already used for in-process retry invalidation and deliberately ignores time-only change; reuse it to keep in-process and cross-Host behavior consistent.
4. **Write only on a safe Campaign Map.** Checkpoint reads/writes must be confirmed by the Native transport and must match the current Campaign identity. If the Host stops during an Encounter/modal/Mission, do not claim the in-memory attempt survived SaveAs; retain the prior verified save.
5. **Keep the LLM responsible for Native choices.** A pending objective resumes its already model-selected route, but every next menu/offer/dialogue choice comes from a fresh Native catalog and a new model decision. Blocked routes are excluded only while the exact Journal and route fingerprint remain unchanged; the Host does not choose the next objective for the model.

## Risks / Trade-offs

- Incorrect outcome classification could block a route that is still feasible. → Only mark `blocked` for explicit no-progress/unavailable outcomes; budget exhaustion and Host stop remain `pending`, and any Journal/fingerprint change reopens the route.
- A route fingerprint may miss a Native availability change. → Use the existing tested fingerprint; add tests for same-fingerprint/time-only behavior and changed menu, settlement target, party, economy, or nearby hostile party.
- The Native save may not include a write made after the last safe SaveAs. → Require a completed Native checkpoint receipt and a verified safe save before claiming restart persistence.
- This memory reduces repeated selection calls but does not ensure that the selected route succeeds or the four Journal targets progress.

## Migration Plan

Old saves without `eycObjectiveAttemptMemoryV1` load with an empty attempt view. The new property remains optional and is bound to the existing Campaign checkpoint. Rollback removes only this optional property interpretation; it does not mutate the Bannerlord world or original Quest state.

## Open Questions

None. The existing source fingerprint and checkpoint APIs cover the scoped behavior; per-Campaign runtime persistence is validated separately from Fake Native/package tests.
