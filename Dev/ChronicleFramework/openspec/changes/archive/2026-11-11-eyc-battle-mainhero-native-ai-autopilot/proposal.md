# Proposal

## Why

The current Host fallback delegates troop formations with F6 but leaves MainHero under player control, so the body the Agent is supposed to play remains stationary while the Mission continues. A zero-model 1.4.8 Native probe reproduced the installed RTS Camera AI handoff sequence and completed one field battle with MainHero moving under Native AI until loot; now that feasibility is established, the existing Host loop needs to use it.

## What Changes

- After the Host chooses the existing ordinary field-battle fallback, finish Native deployment, delegate current troop formations once, then hand MainHero to Native AI for the active Mission.
- Passively observe the same Mission, Native MainHero controller/health, Campaign time, and Native aftermath; do not call the model per frame or force battle outcomes.
- Restore player control when the Mission ends or the bounded loop stops; report Native losses and aftermath without claiming safety from one sample.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `native-battle-mission-delegation`: MainHero is handed to the game's AI during the delegated field Battle Mission and observed through Native aftermath.

## Impact

Native protocol/adapter, `AgentHostBattleMissionLoop`, its Native mailbox client and contract tests, the existing `native-battle-mission-delegation` spec, MAINLINE and issue #132. No new LLM decision or explicit Campaign clock action is introduced.
