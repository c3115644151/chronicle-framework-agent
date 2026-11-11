# Tasks

## 1. Read-only Native AI context

- [x] 1.1 Add the MainAgent Formation's Native ActiveBehavior and current order/target readback to `battleMissionStatus`, plus guarded harness-only Formation AI refresh, Move-order membership notification, and RTSCamera-pattern WatchState/formation-flag handoff; `Run-Harness.ps1 -Phase Build` passed at `TestResults/20261111-104950`, and `Run-Harness.ps1 -Phase Docs` (`TestResults/20261111-105018`) statically confirms no Host action is added.
- [x] 1.2 Run one zero-model `BattleMissionControllerProbe` plus one RTSCamera-pattern `BattleMissionRtsCameraProbe` on the same source checkpoint; `TestResults/20261111-101652` and `105107` passed with same Mission/source hash, both controller restoration paths, Campaign Stop/day, clone deletion and process cleanup. Neither AI-controller pattern moved MainHero; the RTSCamera subset ended at `prisoner_wait` after HP78→8/Party20→0. These are negative movement results, not product-acceptance passes.

## 2. Close the research increment

- [x] 2.1 Update only the existing Research/G and MAINLINE, plus issue #132 evidence; `Set-ContextFocus.ps1 -Review`, `openspec validate --all` (8/8), and `Run-Harness.ps1 -Phase Docs` (`TestResults/20261111-110648`) passed.

## Workflow follow-up

- Archive after the single Native sample. Keep #132 open unless its MainHero control/safety acceptance passes.
