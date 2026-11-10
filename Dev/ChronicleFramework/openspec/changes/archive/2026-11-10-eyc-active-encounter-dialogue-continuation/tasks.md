# Tasks

## 1. Allow forced encounter-line continuation

- [x] 1.1 Remove only the active-encounter exclusion from the no-choice MapState dialogue predicate and add a Fake Native/Provider battle-loop case that continues a text-only `encounter_meeting` line, rereads a newly clickable Native choice, and preserves the existing no-progress stop; verify with `Run-Harness.ps1 -Phase AgentHostPackage` and record the exact TestResults receipt (`TestResults/20261110-214850`, final Fake Native/Provider integration rerun `TestResults/20261110-222018`).
- [x] 1.2 Update the existing G research and MAINLINE mechanism-contract row with the observed active Bandit prompt, Native handler/time evidence, and unverified post-Continue result; run Docs/OpenSpec validation and archive after the package test passes (`TestResults/20261110-215708`; archive `openspec/changes/archive/2026-11-10-eyc-active-encounter-dialogue-continuation`).

## 2. Bounded natural verification

- [x] 2.1 From the current `freshB` checkpoint, run one real-model continuation with at most 20 provider decisions and a ¥0.20 reservation ceiling; verify the no-choice line is advanced once without a model request, then record what Native choices/actions followed, whether the run reaches a checkpointable Map state, and the actual cost. Do not repeat the same save/action combination if the prompt is not reached (`TestResults/20261110-220446`: 18 decisions, estimated ¥0.098825568/¥0.20 ceiling; no provider call for Continue; fresh Map `encounter` menu offered current Fight/escape choices; model opened Native Try-to-get-away warning; next request was rejected before dispatch; state remained unsafe encounter and no checkpoint was written, prior source save retained).
