# Design

## Installed engine path

The local 1.4.8 `SandBox.AgentNavigator.SetTargetFrame` stores a target `WorldPosition` and calls `Agent.SetScriptedPositionAndDirection`; its `Tick` handles path movement. The existing location adapter uses this class only for friendly Town/Tavern/Village missions. This probe tests the same engine helper under a field battle without broadening the production action.

## Probe protocol

1. Load the existing EYC source and create a Native SaveAs clone; verify the source hash remains unchanged.
2. Enter a field Campaign Battle Mission, finish Native deployment, and issue F6 once so troop formations are AI-controlled while MainHero remains Player-controlled.
3. Resolve the nearest active enemy Agent in the same Mission, compute a short navigable target point away from it, and require `Scene.DoesPathExistBetweenPositions` before submitting.
4. Temporarily set MainHero Controller to Native AI, call `AgentNavigator.SetTargetFrame`, and passively tick the Navigator for a fixed short lease. Sample position, health, target distance, Mission state, and Campaign time; do not call the model or mutate Formation, Team, roster, or battle result.
5. Restore Player control on arrival/timeout/Mission end/stop, verify controller and Campaign time, then finish Native aftermath and clean the clone only if its hash matches the SaveAs result.

The active-lease watchdog must recognize its scoped Battle probe owner as AI-controlled; the ordinary Location Navigator has a different execution context. Reusing the Location-only Player-controller guard would clear the Battle lease before its first sample and produce no valid movement result.

## Interpretation

Movement toward the target proves only this Native path can reposition MainHero in one field-battle sample. It does not establish that an enemy-relative point is safe, that retreat/attack logic is complete, or that the product should enter battle. No observed movement or failed path resolution closes this specific route; do not keep retrying the same target/configuration.
