# Tasks

## 1. Bounded Native AgentNavigator test

- [x] 1.1 Add a Harness-only AgentNavigator battle lease with Campaign field-battle/Player/Stop/target-path guards, a separate AI-owner lease predicate, and restoration; verify Build/Docs keep it out of AgentHost and do not change the Location Mission Navigator contract.
- [x] 1.2 Run one no-model field-battle probe with one enemy-relative move target; record movement, health, Native aftermath, Campaign time, source hash, clone removal, and process cleanup. If the lease clears before sampling, classify it as a Harness guard failure and do not interpret it as a game result.

## 2. Record the finding

- [x] 2.1 Update only Research/G, MAINLINE, DEVELOPMENT and issue #132 with evidence/limits; run `Set-ContextFocus.ps1 -Review`, `openspec validate --all`, and `Run-Harness.ps1 -Phase Docs`.

## Workflow follow-up

- Archive after the single Native sample. Do not add a product action or change #132 acceptance until the user resolves the pending F6-only versus MainHero-movement boundary.
