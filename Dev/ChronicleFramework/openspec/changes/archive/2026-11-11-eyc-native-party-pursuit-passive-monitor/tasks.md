# Tasks

## 1. Contract and monitor

- [x] 1.1 Add a bounded passive observer for the already-selected Native Party pursuit. It uses fresh Native state reads only, never issues a clock action, returns on the documented interrupt conditions, and exposes elapsed/poll results. When the encounter opens, Host refreshes the observed party identity without choosing its menu option.
- [x] 1.2 Add deterministic package regressions for active pursuit window expiry, encounter/conversation/incident interruption, Native target loss/stopped time, and Host cancellation. Battle-loop fakes verify no model call is made during the automatic window; monitor contracts assert zero clock/gameplay actions. `TestResults/20261110-234414` passed after all scenarios were added; packaged self-test report has zero real model calls and zero Native gameplay commands.

## 2. Integrate and verify

- [x] 2.1 Run `Run-Harness.ps1 -Phase AgentHostPackage`; record exact receipt and confirm zero real provider/gameplay actions (`TestResults/20261110-234414`).
- [x] 2.2 Update the existing K movement research and MAINLINE evidence with the actual Native pursuit state fields and test receipt. Run `Set-ContextFocus.ps1 -Review` and Docs/OpenSpec validation.
- [x] 2.3 From the same safe `freshB` source, run one continuation capped at 20 provider decisions / ¥0.20 and compare with `TestResults/20261110-220446`. `TestResults/20261110-235029` naturally selected pursuit of `looters_404`: `observeAgain` provider decisions fell 3→1; their estimated cost fell ¥0.01557062→¥0.00504701 (¥0.01052361 less for those waits). The Host passively observed for a 10-second window between `pursue` and the remaining model wait, then the Native encounter opened. This does not prove total-run savings: overall run cost was ¥0.09978960 vs ¥0.09882557 due to different later decisions. The run ended at the ¥0.20 reservation guard after the model repeatedly toggled between the same Native Try-to-get-away warning and rejection; no checkpoint was saved, source checkpoint/hash remained unchanged, game processes cleaned.

## 3. Record monitor evidence

- [x] 3.1 Add secret-free Harness visual-capture trace events for passive pursuit windows and encounter target refresh; self-test recorded stop reason, poll count and no prompt/body fields.
- [x] 3.2 AgentHostPackage `TestResults/20261111-000638` and Docs `TestResults/20261111-001055` passed after final updates. Do not repeat the real-model continuation solely to test logging.
