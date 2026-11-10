# Tasks

## 1. Native battle contract and action

- [x] 1.1 Add a Battle-Mission-only observation for MainAgent controller/health and current player Formation control state; verify schema-level serialization with Build and a narrow Native observer regression. Evidence: `TestResults/20261111-055445` Build; direct observer receipts in `TestResults/20261111-BattleDelegateProbe/Temp/`.
- [x] 1.2 Add the bounded Native `missionDelegateTroops` action using the current player `OrderController` and the original `AIControlOn` order; reject non-battle/ended missions and verify original selection semantics, unchanged MainAgent controller, and unchanged Campaign clock through Build plus AgentHostPackage. Evidence: `TestResults/20261111-BattleDelegateProbe/Temp/MissionDelegateTroops-Retry.json`; package regression `TestResults/20261111-062100`.

## 2. Host Battle-Mission route

- [x] 2.1 Add `missionDelegateTroops` to the Native transport/action catalog only for an active Campaign Battle Mission; Fake Native tests must prove it is offered after the model-selected original `attack` path and rejected from friendly Location Missions or BattleSimulation states; verify with AgentHostPackage. Evidence: `TestResults/20261111-062100`.
- [x] 2.2 Add a bounded Battle-Mission controller that issues the original delegation order once, monitors MainHero and the native Mission outcome without per-frame model calls, and returns to the existing aftermath/Journal verification path; Fake scenarios cover victory, captivity defeat, timeout, and MainHero health risk; verify with AgentHostPackage. Evidence: `TestResults/20261111-062100`.

## 3. Live Native verification

- [x] 3.1 Resume the retained disposable `ChronicleW7P-Vis1111` checkpoint and complete one low-morale looter Battle Mission without model calls; capture Native frames/state proving F6-equivalent delegation, MainHero handling, Campaign time stop, original result, aftermath, and EYC Journal delta; leave the source save hash unchanged and stop/clean processes. Evidence: `TestResults/20261111-BattleDelegateProbe/Temp/MissionDelegateTroops-Retry.json`, `BattleMissionEndedState.json`, `PostBattlePartyState.json`, `AfterBattleExitPoll.json`; the source save hash remained unchanged.
- [x] 3.2 Update the existing MAINLINE and Research/G contract with the observed result and remaining limitations, run Set-ContextFocus review, OpenSpec validation, Build/AgentHostPackage as relevant and Docs, and retain the exact TestResults receipt. Evidence: `TestResults/20261111-062100` AgentHostPackage passed including the model-selected Attack→F6 Host integration fake; `TestResults/20261111-062435` Docs/OpenSpec validation passed; `Set-ContextFocus.ps1 -Review` refreshed the MAINLINE hash.

## Workflow follow-up

- Archive this OpenSpec change after implementation and verification are complete; leave parent Issue #130 In Progress afterward.
