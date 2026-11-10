# Design

## Context

See `proposal.md` for the EYC failure case and user-confirmed F1/F6 behavior. The current Campaign BattleSimulation route is still preferred. The new route is only for a model-selected Native `attack` action when the current Encounter does not enable `str_order_attack`. The installed 1.4.8 source and user observation agree that F6 delegates troop Formations while MainHero stays player-controlled.

## Goals / Non-Goals

**Goals:**

- Reproduce the Native Delegate Command against current player-controlled Formations inside a supported Campaign Battle Mission.
- Preserve MainHero as the Agent's player body and verify its state during the Mission.
- Let the Host observe the original Mission/aftermath lifecycle without model calls on every frame and without changing Campaign time.
- Re-enter the existing Campaign/EYC loop only after native results and aftermath state have been read.

**Non-Goals:**

- Replacing Campaign `BattleSimulation`, changing its morale gate, or forcing `attack` when the model chose another option.
- Directly setting victory, casualties, Roster, Renown, Gold, or Quest progress.
- Delegating siege, hideout, tournament, naval, Army-join, tutorial, or unrelated Mission types in this change.
- Making MainHero AI-controlled by assigning `Agent.Controller=AI`; the user confirms the original F6 order does not do this.

## Decisions

1. **Use the original OrderController operation.** The installed Native UI binds `MissionOrderVM.OrderController` to `Mission.PlayerTeam.PlayerOrderController`. `MissionOrderVM.OpenToggleOrder` selects all Formations when no Formation is selected; `OrderController.SetOrder(OrderType.AIControlOn)` invokes `SetControlledByAI(true)` for the selected Formations and emits the Native delegate command event. The bridge should call the current Native order path, not write Formation flags directly. The product action will be an explicit “delegate current troop formations” operation; the protocol must report which active player Formations changed.
2. **Keep Campaign simulation and real-time Mission paths separate.** `str_order_attack` remains the preferred campaign autoresolve when Native-enabled. Only when it is disabled may the model choose `attack`, and only when that original option is enabled and healthy MainParty troops remain. Native Leave and Try-to-get-away options remain in the catalog. After `attack`, Host waits for Battle Mode, issues Native delegation once, then observes Mission state. No action in this route sends Pause/Resume/Advance/FastForward to the Campaign clock.
3. **Keep MainHero under the Agent.** F6 affects Formations, not MainAgent. The Mission observation distinguishes `MainAgent` controller/health from Formation controller state. A live one-encounter probe ended without MainHero roster injury, but this does not prove safety in larger or different battles. If the Mission controller changes or Native aftermath cannot be reached, the Host returns an explicit failed outcome rather than claiming the fight was resolved.
4. **Use bounded passive observation after delegation.** Once the Native order is issued, poll fresh Mission state without repeated provider requests. Return to planning when the Mission ends, MainHero becomes incapacitated, the current Mission changes, an unsupported modal appears, or the observation deadline expires. Native aftermath remains a separate original UI sequence and must be read/acted on only through its current menus.

## Risks / Trade-offs

- **MainHero remains exposed.** Delegated troops fight while MainHero remains Player-controlled and does not act autonomously. The first live sample recorded no postbattle MainHero roster injury, but battle-scale safety remains unknown; this fallback is not a general battle-autonomy claim.
- **Formation selection differs from UI state.** The Native F6 action applies to selected Formations; the bridge must reproduce current UI selection semantics and must not silently omit units.
- **Battle Mission outcomes may take time.** Passive observation must be bounded and avoid repeated paid model calls. Timeout leaves the current Campaign state and does not save or mark progress.
- **Campaign battle conditions vary.** Low morale is one tested reason for disabled Campaign simulation. Other battle types and mission start/aftermath transitions remain outside this change.

## Migration Plan

No save migration or external dependency. This adds an optional Host action for the current Campaign battle Mission; existing Campaign Simulation and all non-battle Mission paths remain unchanged. A source-hash-verified disposable save is used for the manual runtime probe.
