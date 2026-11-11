# Design

## Native source fact

The installed 1.4.8 `Formation.SetControlledByAI(true)` path ticks the formation AI and applies its movement order only when `AI.ActiveBehavior` exists and the formation has units. `Agent.Controller=AI` is a separate native setter. The first disposable probe changed MainAgent's controller, but MainHero stayed in singleton Formation 8 with unchanged position and health. The missing signal is whether that formation had an ActiveBehavior.

## Probe

- Add `hasActiveAiBehavior`, `activeAiBehaviorType`, `activeAiOrderType`, and the current order target/distance to the current MainAgent formation readback; do not mutate orders.
- Reuse `BattleMissionControllerProbe` once on the same source Campaign fixture, with F6 troop delegation then two bounded leases: (a) MainHero remains Mission.MainAgent while Controller=AI; (b) MainHero remains AI-controlled while a same-team AI soldier is temporarily set to Controller=Player, making that soldier Mission.MainAgent. The second variant changes the temporary battle camera/player body and is test-only.
- During variant (b), after two MainHero observations, refresh its already AI-controlled Formation with Native `SetControlledByAI(false)` then `SetControlledByAI(true)`. Keep the original state true on exit and record its ActiveBehavior/current order before and after; do not alter the Formation roster or order.
- If still stationary, reproduce RTSCamera's Native movement-order notification by calling the installed 1.4.8 current `MovementOrder.OnUnitJoinOrLeave(formation, MainHero, true)` while its current order is `Move`; the bridge must reject other order types. Record position, health, and order-target distance for the remaining lease.
- Run a separate controller-only lease that keeps MainHero as Mission.MainAgent and mirrors the installed-source subset of RTSCamera's free-camera handoff: set Native WatchState Alarmed, clear the current version's private `IsPlayerTroopInFormation` flag, and notify the current Move order. Restore both fields with the original controller on timeout/end/stop.
- Preserve status samples, controller restore, stopped Campaign clock, source hash, clone cleanup, and Native aftermath checks.

## Decision rule

- If Formation 8 has no ActiveBehavior while MainAgent is AI-controlled, the standalone controller does not provide an AI objective; research a Native player-side Formation assignment or end this route.
- If an ActiveBehavior is present but position remains fixed, compare current position to the reported Native order target. If already at target, the behavior has no movement demand in that sample; if displaced and still stationary, the cause remains unresolved.
- If the status field is absent, stale, or the clone/test does not reach the same field Battle Mission, mark the probe inconclusive and do not add product behavior.

This is diagnostic only. The refresh temporarily toggles the same Native Formation AI flag and restores it to true; it does not change Formation membership, Team, or movement order. The order callback refreshes only the existing Native Move order's behavior values for the MainHero. The surrogate variant only changes Native controllers and Mission.MainAgent within the disposable Mission and restores both on timeout/end/stop. The RTSCamera-pattern variant changes only controller/watch/formation-player flags in a disposable Mission and restores their saved values; none change Campaign time.
