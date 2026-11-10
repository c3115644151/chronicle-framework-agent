# Proposal

## Why

The latest natural StoryMode continuation reached an active Bandit encounter, selected the current Native Fight response, then landed on a MapState threat line with no clickable answers and a visible “点击继续” prompt. The BattleSimulation child excludes every active encounter from its no-choice continuation path, so it stopped before the original conversation could reveal the next Native choice and the run could not save a new checkpoint.

## What Changes

- Advance the original Native `dialogueContinue` only for the current MapState encounter conversation when it has visible text and no clickable options.
- Re-read Native state after each Continue; present any newly visible choices to the model without selecting them automatically.
- Keep Mission conversations, unrelated prompts, explicit clock actions, and Native encounter choices outside this change.

## Capabilities

### New Capabilities

- `native-encounter-dialogue-continuation`: safely expose forced no-choice text advancement inside an active map encounter.

### Modified Capabilities

None.

## Impact

`AgentHostBattleSimulationLoop`'s existing no-choice Map conversation route and its Fake Native/package regression. No new Native action, player control, or GitHub issue. Parent issue: [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130).
