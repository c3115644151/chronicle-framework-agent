# Design

## Context

See `proposal.md` for the live evidence and motivation. The production Host's `IsSafeObjectiveAttemptCheckpointState` currently requires `encounterActive=false`. That is too strict for settlement menus: the Native Town context reports `encounterActive=true` with `encounteredPartyId` equal to the current settlement. Separately, `Test-AgentLiveModelLoop.ps1` permits a settlement checkpoint only when the same settlement is not besieged and, in `town_backstreet`, the current Native Back/Leave action is enabled. The Host should use the same Native distinction between a settlement encounter and a Party encounter.

## Goals / Non-Goals

**Goals:**

- Load and persist the existing same-Campaign objective-attempt record from verified Town/Village/Castle menus.
- Resume a matching pending objective before asking the model to select another EYC objective.
- Keep the Native state checks narrow and covered for both safe settlement menus and unsafe hostile encounters.

**Non-Goals:**

- Change movement, menu, interaction, Campaign time, encounter or save behavior.
- Treat a Tavern Mission, siege, arbitrary modal, hostile Party encounter or unleavable Backstreet as a checkpoint.
- Add another model provider call or infer a new EYC route.

## Decisions

- Extend the Host's objective-memory checkpoint predicate to match the existing verified Harness save boundary: allow an unobstructed free Campaign Map, or a current non-sieged settlement menu with matching encounter/settlement identity. On `town_backstreet`, require the currently listed enabled `town_backstreet_back` Leave option.
- Keep the rule local to EYC attempt-memory reads/writes; do not broaden other save or gameplay actions.
- Test the production Host restart through a fake Native checkpoint that loads the pending record at `town_backstreet`. The model-facing objective planner must receive zero calls and the child executor must receive the saved objective. A hostile looter encounter and an unavailable Leave option remain rejected.
- Use the next bounded same-save runtime continuation only after deterministic package and Docs checks pass; cost ceiling remains explicit and the retained original checkpoint remains authoritative if no safe Native save results.

## Risks / Trade-offs

- **A hostile Party could be mistaken for the settlement encounter** → Require exact `encounteredPartyId == currentSettlementId` and validate the current settlement record, type and siege status.
- **The Host might persist in a menu the player cannot leave** → Reject `town_backstreet` unless its current Native Leave option is available and enabled.
- **A fresh Journal may differ from the saved attempt** → Keep the existing Journal fingerprint reconciliation; a changed snapshot discards the stale attempt before route execution.

## Migration Plan

Existing saves are unchanged. Old saves without the objective-attempt property continue with empty attempt memory; the new eligibility only affects when the Host reads/writes the optional field.
