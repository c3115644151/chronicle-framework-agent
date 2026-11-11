# Tasks

## 1. Native handoff probe

- [x] 1.1 Add an opt-in Harness-only bounded handoff that reproduces the installed Native AI initialization sequence and restores the captured MainAgent/Formation/controller state; verify `Run-Harness.ps1 -Phase Build` and that AgentHost gains no action.
- [x] 1.2 Run one no-model `BattleMissionNativeAiHandoffProbe` on a hash-verified disposable EYC field-battle clone, holding Native AI until the battle ends or the 180-second lease expires; record movement/health/formation, Native aftermath, Campaign time, source/clone hashes and process cleanup.

## 2. Evidence and closeout

- [x] 2.1 Correct the partial-probe interpretation in Research/G, MAINLINE and DEVELOPMENT; sync issue #132 evidence, run `Set-ContextFocus.ps1 -Review`, `openspec validate --all`, and `Run-Harness.ps1 -Phase Docs`.

## Workflow follow-up

- Archive this feasibility probe after the documented Native result. Keep #132 In Progress until its product acceptance is met; do not treat this probe as completion.
