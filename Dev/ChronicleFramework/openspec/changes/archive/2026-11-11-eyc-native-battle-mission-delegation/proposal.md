# Proposal

## Why

The EYC manual campaign reached an encounter where Native `str_order_attack` was disabled by low morale despite the MainParty having eleven healthy troops. The only winning route was the original real-time Battle Mission, while Chronicle has no Battle-Mission order bridge. The user confirms F6 delegates troops to Native AI but leaves MainHero player-controlled.

## What Changes

- Add a bounded bridge for the Native Battle-Mission “Delegate Command” order (`AIControlOn`) and verify which current formations it delegated.
- Let the EYC host enter that route only after the model selects the enabled Native `attack` option and a Battle Mission is confirmed.
- Observe the MainHero and Native battle lifecycle until the original Mission result/aftermath is available; do not report a win from delegation alone.
- Preserve MainHero as the Agent-controlled body. If the Agent cannot keep MainHero safe or finish the original result flow, return an explicit unsupported/failed result instead of claiming the EYC objective progressed.

## Capabilities

### New Capabilities

- `native-battle-mission-delegation`: delegate Native troop Formations to the game AI during a Campaign Battle Mission and verify the Mission’s original outcome while MainHero remains under Agent control.

### Modified Capabilities

None.

## Impact

`AgentProtocol`/`AgentObserver`, the AgentHost battle and Campaign loops, `Agent-Cli.ps1`, existing BattleSimulation regression tests, `Research/G/BattleAndTactics.md`, `Focus/MAINLINE.md`, and the parent product gate #130. No new model provider or Campaign-time command is introduced.
