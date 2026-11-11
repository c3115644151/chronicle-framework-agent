# Design

## Probe boundary

The reference RTSCamera source is older than the installed game. Adapt only semantics confirmed in current 1.4.8: switch MainAgent Controller to AI, set its WatchState Alarmed, clear the current `Formation.IsPlayerTroopInFormation` marker through its private setter, and notify the current Native Move order that MainAgent joined. The action is harness-only and the test uses a disposable field-battle clone.

## Restore contract

The bounded lease records original Controller, WatchState, and player-troop formation flag, keeps Campaign time stopped, and restores all three on timeout, battle change/end, protocol stop, or explicit cleanup. The test requires the post-restore Native status to match the original values.

## Evidence meaning

Harness pass means the probe ran, restored state, and cleaned up. It does not mean MainHero movement succeeded. Position/health and the original Battle aftermath determine whether the reference path produced an observable result. A no-movement or capture outcome is a negative test result, not a crash.
