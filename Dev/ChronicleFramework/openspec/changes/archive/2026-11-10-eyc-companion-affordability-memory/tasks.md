# Tasks

## 1. Persist Native unaffordable-candidate observations

- [x] 1.1 Extend the existing same-Campaign Companion memory to validate, read, write, and reconcile bounded Wanderer Hero IDs with the Gold balance recorded after the Native no-pay response; add no-model codec regressions for round-trip, unrelated PartySize progress, Gold decrease, and Gold increase, verified by AgentHostPackage (`TestResults/20261110-201422`).
- [x] 1.2 Wire the exact current Native `player_companion_hire_response_2` success into that memory and filter only matching Heroes while current Gold has not increased; add Fake Native/Provider regressions that preserve other candidate IDs, never record absent/stale responses, and reopen a candidate after Gold rises, verified by AgentHostPackage (`TestResults/20261110-201422`, final post-checkpoint-trace rerun `TestResults/20261110-202536`).

## 2. Verify checkpoint integration and documentation

- [x] 2.1 Extend the opt-in zero-model EYC checkpoint readback or its existing Host package fixture to prove the candidate memory survives same-Campaign restart with 0 Provider calls, while keeping the prior Gold/Party/renown/companion source values intact; record the exact TestResults receipt (`TestResults/20261110-201422`; Campaign fixture `campaign-affordability-fixture`).
- [x] 2.2 Run `Run-Harness.ps1 -Phase Docs`, archive this OpenSpec change only after all required task receipts pass, sync the stable `companion-search-recovery` spec, and record the evidence in Focus/MAINLINE.md without closing GitHub #130 (`TestResults/20261110-202917`; archive `openspec/changes/archive/2026-11-10-eyc-companion-affordability-memory`).

## Workflow follow-up

- Keep the next real-model run behind the current ¥0.20 ceiling and use the new checkpoint only after the no-model regressions pass; compare provider-decision count, spend estimate, objective result, and Native checkpoint before deciding whether another live run is useful.
