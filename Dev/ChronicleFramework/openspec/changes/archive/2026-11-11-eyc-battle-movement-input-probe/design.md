# Design

## Probe setup

Reuse the current opt-in Battle Mission fixture: load the verified EYC source, create/delete a disposable SaveAs copy, pursue its harness looter, use Native Ready, and delegate troop formations with F6. Keep MainHero Player-controlled and Campaign time stopped.

## Input lease

The current Location Mission adapter writes the player's movement vector after Native `MissionMainAgentController.ControlTick` and clears it on a short application-time lease. Add a separate Harness-only Battle guard and lease flag so the same post-tick write can be tested in an ordinary Campaign field battle without widening the production action. Apply one bounded vector for at most 0.5 seconds, sample MainHero position/health before and after, and clear it on expiry, Mission change/end, or stop.

## Evidence meaning

Movement and time are measured separately. If position changes during the input lease while Campaign remains stopped, this proves only that a single player-like movement pulse works in this battle setup; it does not prove safe navigation, tactical autonomy, or a complete action loop. If the pulse is rejected or no movement is observed, do not add it to AgentHost.
