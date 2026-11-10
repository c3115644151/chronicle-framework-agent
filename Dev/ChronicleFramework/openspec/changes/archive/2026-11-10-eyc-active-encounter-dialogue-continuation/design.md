# Design

## Context

`AgentHostBattleSimulationLoop` already advances no-choice Native Map conversations before making a Renown decision, but currently requires the encounter to be inactive. Natural Campaign evidence `TestResults/20261110-210622` shows an active `encounter_meeting` whose current looter conversation has visible text, no clickable options, `campaignDay=91089.861`, and `TimeControlMode=Stop`. The final Native frame displays “点击继续”. The run stopped at the next BattleSimulation decision budget boundary, so the actual post-Continue response is not yet observed.

## Goals / Non-Goals

**Goals:**

- Advance only the forced current line through the existing Native ConversationManager action.
- Expose the next fresh Native choices to the model; preserve model ownership of encounter decisions.
- Never add a time-control command or choose an option when none is required.

**Non-Goals:**

- Auto-select Fight/Barter/Surrender/Leave or simulate a real-time battle.
- Continue MissionState or unrelated dialogue in this BattleSimulation branch.
- Claim Renown, victory, or checkpoint progress from a Continue action.

## Decisions

- Remove only the `!activeEncounter` restriction from the existing no-choice MapState conversation predicate. Retain requirements for a current Native Conversation, non-empty sentence, zero clickable choices, and MapState.
- Keep the existing 32-line bound, exact same-text/no-progress stop, fresh-state reread, and no-time-action behavior.
- Add a Fake Native case starting in an active `encounter_meeting` with a no-choice line; after Continue it exposes current Native Fight choices, which the fake Provider must select before the battle path can advance. Assert no model request is issued for the forced Continue itself.

## Risks / Trade-offs

- A current encounter conversation could contain a no-choice line that is not the observed Bandit prompt. The shared safety rule is based on Native MapState/current conversation/no-clickable-option facts, advances one line at a time, and yields as soon as a clickable option appears; identical no-progress text is not repeated.
- A real model run can still stop on the following choice or battle route. The new Native state must be recorded separately from the forced Continue result.
