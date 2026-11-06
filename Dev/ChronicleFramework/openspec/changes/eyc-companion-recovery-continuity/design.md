# Design

## Context

See `proposal.md` and the four behavior requirements in `specs/companion-search-recovery/spec.md`. The game already has a save-backed Chronicle checkpoint in `ChronicleCampaignBehavior.SyncData`, scoped by `AgentCampaignInstanceId`; the mailbox exposes `agentCheckpointGet` and `agentCheckpointSet` only in Campaign MapState. This avoids introducing a second per-campaign file beside the user's save.

Verified receipts:

- `TestResults/20261107-043410`: a prior Host's search memory was read from the saved Native campaign and matched the same EYC Journal snapshot.
- `TestResults/20261107-050137`: the MainParty resumed the existing EW2 move after two visible-Bandit interruptions, then continued to EW3 without repeating the move.
- `TestResults/20261107-053329`: the Native battle route handled a one-person-party surrender and ransom recovery; no battle victory or Renown was claimed. PartySize remained 1 and the run stopped at its cost ceiling before recruiting.
- `TestResults/20261107-051813`: package contracts verify that a monitor-confirmed Bandit pause takes priority over generic stopped-move recovery.

## Goals / Non-Goals

**Goals:** retain trustworthy negative Tavern observations in the current Campaign save; avoid redundant Native movement after nested objective restarts; route only a current, Native-confirmed hostile Bandit interruption into the existing BattleSimulation/Captivity recovery; keep model calls within the existing per-run budget.

**Non-Goals:** change any Native quest, battle, party, ransom, or clock mechanic; infer unseen Wanderers or remote parties; auto-pick multi-option dialogue, ransom, battle, recruitment, or other meaningful choices; declare any EYC objective complete without the Native Journal.

## Decisions

1. **Use the existing Native save checkpoint, not a sidecar file.** The checkpoint already has a Campaign identity and is serialized by the Native Campaign behavior. Read it at Companion-subflow start; write only after a no-candidate Tavern has exited to a safe Campaign MapState. Preserve unrelated checkpoint fields and reject a mismatched Campaign ID.
2. **Scope no-candidate memory to forward EYC progress.** Save the exact four-objective snapshot with the empty-town IDs. A positive objective value change or a changed target clears the old list; a decrease such as Gold spent on ransom updates the snapshot but keeps the exclusions. This prevents resource loss from causing a full duplicate Tavern search.
3. **Automate only no-choice Native transitions.** `missionSceneAgents` is read-only perception and is fetched without spending a model decision. If its fresh roster has no eligible Wanderer and the current Native catalog has only `missionLeave`, submit that original handler and wait for MapState. Candidate selection, navigation, conversation, and offers remain model decisions.
4. **Inherit the current Native settlement target on child restart.** If MainParty is already on an original `GoToSettlement` order, keep that target in the resumed Companion subflow and use the existing passive movement monitor. Do not query/reissue the same `move` while it remains active.
5. **Order hostile interruption routing before generic paused-move retry.** Only a fresh MapState plus the movement monitor's hostile-Bandit interruption code enables BattleSimulation. Other paused settlement moves continue through the existing parent Move recovery. If Native exposes no Send Troops action, the model uses the visible original options; a surrender/ransom path must return to Map before EYC planning resumes.
6. **Log only a bounded memory summary.** Runtime diagnostics expose checkpoint read/write status, remembered-town count, and Journal-match/invalidation flags. They omit town IDs, prompt text, and model arguments.

## Risks / Trade-offs

- A native scene scan can be empty at one visit while a Wanderer may appear later. The memory is intentionally cleared after forward EYC Journal progress, but a no-progress campaign with all safe towns exhausted may still need a later retry policy; do not invent a spawn interval without Native evidence.
- A battle route can end in surrender when the Party has no troops. Native captivity recovery can restore the MainHero, but this may cost Gold and does not count as battle or Renown progress.
- The current memory invalidation refinement and the end-to-end hostile interruption require a fresh bounded run after package validation. Package self-tests alone do not prove that the original EYC quest advances.

## Rollback

The checkpoint extension is an optional Chronicle-owned JSON property. On any invalid/mismatched checkpoint, fail closed or discard only `eycCompanionSearchMemoryV1`; do not rewrite the Native world or alter existing checkpoint fields. The movement-inheritance change can be disabled without changing the saved game state.
