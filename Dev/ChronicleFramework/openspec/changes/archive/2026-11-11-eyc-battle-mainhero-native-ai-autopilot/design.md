# Design

## Context

See `proposal.md` for motivation and `specs/native-battle-mission-delegation/spec.md` for the updated behavior contract. The current `AgentHostBattleMissionLoop` completes the Native Deployment screen, issues F6 once, hands MainHero to Native AI, and passively polls until Native aftermath. The observed game is Bannerlord 1.4.8; the installed RTS Camera 5.4.16 code and Chronicle's zero-model Harness tests establish the Native AI handoff recipe and one Host-owned ordinary field-battle slice.

## Goals / Non-Goals

**Goals:**

- Give MainHero the Native AI controller only in the current supported ordinary field Battle Mission, after a successful F6-equivalent delegation.
- Complete the original Native Deployment path before F6: use Native Auto Deploy when the Ready callback is missing, then run the original Ready command and verify Battle mode.
- Let the Host observe MainAgent's controller and health while it passively waits for the Native Mission result.
- Restore the captured state on Mission end/change, Host stop, or the same 15-minute bounded loop limit.

**Non-Goals:**

- No per-frame LLM or real-time model polling; no new model-visible action; no custom movement or combat solver.
- No siege, hideout, alley, tournament, naval, or other Mission categories.
- No edits to damage, survival, roster, renown, outcome, or Campaign time.
- No success or safety claim based on a single battle.

## Decisions

1. **Use a Host-owned Native control lease.** After the Host's current attack decision and once-only F6 order, a private Native protocol action reproduces the tested AI setup: clear interaction focus, AI controller, required equipment/AI flags, AI component initialization, alarmed watch, unpause, clear scripted movement, refresh Formation/order membership, and deactivate the Native player input controller. The current Host's 900-poll/15-minute completion bound is also the lease cap. This is not exposed in the model action catalog.
2. **Preserve the Native Deployment UI setup.** The Native `OrderOfBattleVM` may display the Deployment view before `_onBeginMission` is initialized. The Host first calls the original `MissionGauntletSingleplayerOrderUIHandler.OnAutoDeploy` path, followed by the existing F1 `MissionOrderDeploymentControllerVM.ExecuteDeployPlayerSide` handler to finalize player-side placement and run `OnPlayerTeamDeployed`; it then calls `OrderOfBattleVM.ExecuteBeginMission` so current formation filters are saved. If the original Ready callback is missing after that initialization, the Host calls its Native callback target, which follows the original F1 `OnFiltersSet` / `ExecuteBeginMission` route. It never calls `DeploymentHandler.FinishDeployment` directly. If that Native UI callback throws after the transition, the Host checks Native Mission mode, `IsDeploymentFinished`, and Campaign `Stop`; it continues only when all prove the original transition occurred and never replays Ready.
3. **Keep the Host as the mission owner.** `AgentHostBattleMissionLoop` waits for the MainAgent to become Player-controlled in Battle mode, issues F6 once, hands off Native MainHero AI once, and reads state passively until Native aftermath. It records health loss and returns only the original result. It issues no Campaign clock actions or model requests during the Mission.
4. **Restore captured state, do not normalize it.** Capture controller, AI/watch/agent flags, pause state, formation membership and Native controller activation before handoff. Restore them on partial setup failure, expiry, Mission change/end, or protocol stop. On mission end, accept the outcome the game produced.
5. **Keep the previous Human-control fallback closed.** If the handoff preconditions or postconditions fail, the Host does not pretend the hero is under Native control and does not issue the same non-idempotent transition repeatedly. The result is marked unresolved for the parent loop.

## Risks / Trade-offs

- Native AI may move or fight MainHero differently across equipment, terrain, formations, and battle sizes → keep the feature limited to ordinary field battles, record health/outcome, and do not claim a safety rate from the single 1.4.8 sample.
- Native AI may be interrupted by another mod or change in a later version → validate controller and Mission state after handoff and fail closed when they diverge.
- The original Ready callback can throw after changing Mission to Battle → reconcile against fresh Native state, keep the exception class in the receipt, and proceed only when Battle mode, deployment-finished, and Stop are verified.
- MainHero may be wounded, captured, or killed by the original battle → preserve Native consequences and let the existing Campaign recovery path handle them; never edit results.
- The user cannot redirect tactics through new LLM calls during battle → F6 and Native battle AI handle execution; strategic choice remains with the Agent before entry, and the Host resumes after the Native result.

## Migration Plan

No save migration. The Native action is internal; if its guard or restore fails, Host reports an unresolved battle transition and the existing Mission-stop cleanup runs.

## Open Questions

None for the bounded ordinary field-battle integration. Cross-Mission support remains explicitly out of scope.
