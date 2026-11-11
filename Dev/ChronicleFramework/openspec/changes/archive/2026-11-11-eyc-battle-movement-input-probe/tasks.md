# Tasks

## 1. Bounded Native movement probe

- [x] 1.1 Add a Harness-only battle input lease that passes the exact field-Battle/Player/Stop guards, runs after Native ControlTick, and clears on timeout/end/stop; Build passed at `TestResults/20261111-112854`, Docs/static guards passed at `TestResults/20261111-112959`, and the production Location `missionInput` guard and AgentHost action catalog remain unchanged.
- [x] 1.2 Run one zero-model `BattleMissionMovementInputProbe` on the existing source checkpoint with a single 0.5-second retreat-relative input; `TestResults/20261111-113445` showed 0.226 units of movement, Campaign Stop/day unchanged, source hash unchanged, clone removed, and clean process exit. The battle outcome is recorded separately and not attributed to the input pulse.

## 2. Record the result

- [x] 2.1 Update only the existing Research/G, MAINLINE, and issue #132 with the result and limitations; `Set-ContextFocus.ps1 -Review` ran at `2026-11-11T03:39Z`, `openspec validate --all` and `Run-Harness.ps1 -Phase Docs` passed at `TestResults/20261111-113955`.

## Workflow follow-up

- Archive after the single movement probe. Do not change #132's acceptance or expose battle input in AgentHost until the user resolves the battle-risk boundary.
