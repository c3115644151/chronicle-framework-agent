# Tasks

## 1. Native handoff probe

- [x] 1.1 Add the opt-in `BattleMissionRtsCameraProbe` phase and bounded RTSCamera-style Harness command; its Build stage passed at `TestResults/20261111-105107`, and static Docs/OpenSpec validation passed at `TestResults/20261111-110648` while keeping the command outside AgentHost.
- [x] 1.2 Run the Native probe on the existing disposable Campaign source; `TestResults/20261111-105107` passed with 0 model calls, source hash unchanged, clone removed, all temporary controller/watch/formation state restored, and process stopped. MainHero did not move, health fell 78→8, and the original outcome was `prisoner_wait` with Party20→0.

## 2. Evidence and handoff

- [x] 2.1 Update Research/G, MAINLINE, DEVELOPMENT, and issue #132 with the negative result and limitations; validate OpenSpec and run `Run-Harness.ps1 -Phase Docs` (`TestResults/20261111-110648`).

## Workflow follow-up

- Keep issue #132 open until the user resolves whether F6-only delegation with Native risks is acceptable or MainHero movement is required.
