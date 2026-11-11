# Tasks

## 1. Reversible Native probe

- [x] 1.1 Add a harness-only bounded MainAgent AI-controller lease with guards for the active ordinary Campaign field Battle Mission, Player-controlled MainAgent, stopped Campaign clock, same-Mission identity, and automatic Player restoration on timeout/end/stop; verify `Run-Harness.ps1 -Phase Build` (`TestResults/20261111-092037`) and `Check-Docs.ps1` statically enforce the probe guards, bounded restoration, and exclusion from AgentHost.
- [x] 1.2 Extend the opt-in disposable Battle Mission probe to collect MainAgent baseline and interval samples during the AI lease, restore Player control, verify Campaign time/source-save hash/clone cleanup, and run `Run-Harness.ps1 -Phase BattleMissionControllerProbe`; evidence `TestResults/20261111-092652` passed with 0 model calls, unchanged source hash, deleted clone, Player restoration, and postbattle PartyState.

## 2. Record the evidence

- [x] 2.1 Update only the existing `Research/G/BattleAndTactics.md`, `Focus/MAINLINE.md`, and issue #132 with the result and its limits; `Set-ContextFocus.ps1 -Review`, `openspec validate --all` (8/8), and `Run-Harness.ps1 -Phase Docs` (`TestResults/20261111-093313`) passed.

## Workflow follow-up

- Archive this change after the Native probe has a clear result. Do not close #132 or change parent #130 based only on a probe sample.
