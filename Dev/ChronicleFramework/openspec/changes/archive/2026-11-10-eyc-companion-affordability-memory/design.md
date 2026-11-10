# Design

## Context

The Companion loop already excludes a Hero after a no-pay response for the current Host run, but `AgentHostEycCompanionSearchMemory` persists only empty-Tavern Town IDs. The same Campaign therefore re-opened the same 432-denar quote after a safe checkpoint/Host restart, first with 424 Gold and then 64 Gold. See `TestResults/20261110-191922` and `TestResults/20261110-194230`; the second attempt used 16 model decisions and about ¥0.102, then safely checkpointed without Companion progress. `TestResults/20261110-194900` confirms the new save is the same Campaign, Gold64, Companion0/1, and the Companion attempt remains pending.

## Goals / Non-Goals

**Goals:**

- Suppress only the exact Wanderer previously declined as unaffordable.
- Preserve that observation across same-Campaign Host restart and unrelated Journal progress.
- Reopen the candidate after Gold increases, leaving the current Native conversation as the final eligibility check.

**Non-Goals:**

- Parse localized dialogue text or infer a denar quote from markup.
- Mark all Companion hiring unavailable because one Wanderer is too expensive.
- Add a new Native action, bypass hiring handlers, or change the objective planner.
- Run another paid model test to validate the memory codec.

## Decisions

- Record an entry only after the Native response action for the exact `player_companion_hire_response_2` option succeeds and the current conversation identifies its Hero. Capture the current Native MainHero Gold before submitting the response.
- Store a bounded list of `(HeroId, goldAtRefusal)` entries in the existing Campaign checkpoint. This is separate from `noCandidateTownIds`; it must survive unrelated Journal progress and Gold decreases.
- Filter the exact Hero from current scene candidates while `currentGold <= goldAtRefusal`. Remove stale entries when Gold increases above the recorded balance. Do not filter another Wanderer or the entire Town.
- Keep this memory in-process while inside a Mission and persist only after the existing verified return to safe Native MapState. Do not write the formal save or store dialogue/prompt text.

## Risks / Trade-offs

- If the same Wanderer later changes its hiring price without the player's Gold increasing, the remembered entry can delay a fresh check. The limited rule only activates after Native itself exposes the no-pay response; a Gold increase reopens it, and a different Hero remains eligible.
- Hero ID must remain stable across the same Campaign save. The existing Host uses that Native Hero identity for Tavern candidate matching; package tests must reject malformed or duplicate memory entries.

## Migration Plan

Read existing `eycCompanionSearchMemoryV1` checkpoints as before. Treat a missing unaffordable-candidate array as empty, and write the new bounded field on the next verified safe checkpoint. No save migration or deletion is required.
