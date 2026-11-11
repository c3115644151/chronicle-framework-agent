# native-battle-mission-delegation Specification

## Purpose

This capability lets the Campaign Agent use Bannerlord's original battle-mission delegation order when Campaign-level battle simulation is unavailable, while keeping the MainHero under Agent control and verifying the Native battle outcome.

## Requirements

### Requirement: Delegate current troop formations through the Native battle order
When the Agent has entered an original Campaign battle Mission and requests troop delegation, Chronicle SHALL apply the Native Delegate Command to the current player-controlled Formations and report which Formations the Native order changed.

#### Scenario: Delegation succeeds in a supported Battle Mission
- **GIVEN** the current state is an active Campaign Battle Mission with a valid player order controller and at least one current player Formation
- **WHEN** the Agent requests Delegate Command
- **THEN** the original Native order changes the selected current Formations to AI control, the bridge reports the affected Formations, and the MainHero controller remains player-controlled

#### Scenario: Delegation is rejected outside a supported Battle Mission
- **GIVEN** the current state is a Campaign Map, friendly Location Mission, non-battle Mission, or completed Mission
- **WHEN** the Agent requests Delegate Command
- **THEN** the bridge rejects the action without changing a Formation, MainAgent controller, Campaign state, or time mode

### Requirement: Delegation does not count as a battle result
After Native troop delegation in the supported ordinary Campaign field Battle Mission, the Host MUST hand MainHero to the game's Native AI controller and passively observe MainHero and Mission state until the Mission ends or the bounded Host loop terminates. The Host MUST NOT report success until it reads the Native aftermath, and MUST NOT issue per-frame model requests, change Campaign time, or write battle outcomes.

#### Scenario: Troops delegated while the MainHero remains under Agent control
- **GIVEN** the Host has entered the supported ordinary field Battle Mission, completed its current Native Deployment setup, and the Native Delegate Command has changed one or more current Formations to AI control
- **WHEN** the Host starts its MainHero Native AI handoff
- **THEN** the same MainAgent remains the MainHero under the Host's mission lease, its Native controller reads as AI, the Native player-input controller is inactive, the original Campaign time mode remains Stop, and the Host begins passive Mission observation without another model call

#### Scenario: MainHero handoff is rejected or cannot be verified
- **GIVEN** the current Mission, MainAgent, Campaign clock, or required Native AI components do not satisfy the handoff guard
- **WHEN** the Host attempts the handoff
- **THEN** the bridge rejects without changing Campaign time or battle outcomes, restores any state already changed by the handoff, and the Host returns an explicit unresolved result rather than claiming a battle result

#### Scenario: Native battle result returned
- **GIVEN** the MainHero Native AI handoff remains active until the original Mission ends and the game enters its Native aftermath
- **WHEN** the Host reads the resulting state
- **THEN** it returns the observed outcome, current MainHero health/controller state, and current Roster/Journal changes without calling the battle a victory before Native evidence supports it

### Requirement: Use the original Attack Mission only as the no-Send-Troops fallback
When the current hostile Bandit Encounter has Native `str_order_attack` disabled but exposes the original enabled `attack` option and the current MainParty has healthy troops, the Host MAY enter the original ordinary field Battle Mission only to finish Native deployment, delegate current Formations once, hand MainHero to Native AI, and passively observe the Mission. It MUST keep Native Leave and Try-to-get-away choices available before entry, MUST NOT issue Campaign clock commands, and MUST NOT send per-frame model requests during the Mission.

#### Scenario: Send Troops is available
- **GIVEN** the current Native Encounter enables `str_order_attack`
- **WHEN** the model chooses a combat action
- **THEN** the Host exposes the Native Send Troops path and does not expose `attack` as a real-time Mission alternative

#### Scenario: Send Troops is disabled and healthy MainParty troops remain
- **GIVEN** the current Native Encounter disables `str_order_attack`, enables `attack`, and the current MainParty reports at least one healthy member
- **WHEN** the model chooses the current Native `attack` option
- **THEN** the Host enters the original field Battle Mission, completes Native Auto Deploy/Ready setup as needed, delegates current Formations once, starts the guarded MainHero Native AI handoff once, and observes the Native result without additional model or Campaign clock actions

#### Scenario: Send Troops is disabled and no healthy troops remain
- **GIVEN** the current Native Encounter disables `str_order_attack` and the current MainParty has no healthy members
- **WHEN** the model is offered encounter actions
- **THEN** the Host does not expose the real-time `attack` option and leaves only currently enabled Native exit/survival choices

### Requirement: Finish the current Native field deployment before troop delegation
After the original Campaign Attack option enters a supported field Battle Mission in Deployment mode, the Host MUST finish Native Deployment through the current original Native UI handlers, verify the same Mission reaches Battle mode, and only then issue the existing F6-equivalent troop delegation once. The Host MUST NOT directly call DeploymentHandler.FinishDeployment, call the model during this transition, or change Campaign time.

#### Scenario: Native field deployment advances to Battle
- **GIVEN** the current Mission is an active hostile Campaign field battle in Deployment mode, MainHero may not yet be spawned, and no Inquiry is open
- **WHEN** the bounded Native deployment-finish operation completes
- **THEN** the Host observes the same Mission in Battle mode before issuing troop delegation, keeps Campaign time stopped, and does not request another model decision during the transition

#### Scenario: Native Ready callback is not initialized
- **GIVEN** the original Order of Battle view is present in Deployment mode, Ready is enabled, but its callback is not bound
- **WHEN** the Host prepares a normal field battle
- **THEN** it invokes the original Native Auto Deploy path and the player-side deployment callback once, then commits the original Ready configuration once
- **AND** it confirms the same Mission reached Battle with deployment finished and Campaign time still Stop before issuing F6

#### Scenario: MainAgent is absent or not Player-controlled before Battle
- **GIVEN** Native Deployment mode has no active MainAgent or the MainAgent controller is not Player
- **WHEN** the Host prepares the battle
- **THEN** this pre-Battle controller state alone does not block Ready; after Battle starts, the Host waits for the same MainAgent to read as Player-controlled before issuing F6 or Native AI handoff

#### Scenario: Deployment cannot safely finish
- **GIVEN** the current Mission is not an eligible Campaign field battle, is already ended, has an active Inquiry, or the Native Order of Battle Ready control is unavailable
- **WHEN** the Host attempts to finish Deployment
- **THEN** it rejects or stops without issuing troop delegation, changing Campaign time, or claiming a battle result

#### Scenario: Native callback reports an error after the state transition
- **GIVEN** the original Native Ready callback reports an exception
- **WHEN** the Host reads fresh state and finds the same Mission in Battle, deployment finished, and Campaign time Stop
- **THEN** it records the exception class, accepts the verified Native transition, and never repeats Ready

#### Scenario: Native deployment finish is rejected or ambiguous
- **GIVEN** the original Native deployment-finish operation was submitted
- **WHEN** the handler rejects it, times out, or the same Mission fails to reach Battle mode within the bounded observation window
- **THEN** the Host does not repeat the non-idempotent operation, does not send F6, and returns an explicit unresolved transition result

### Requirement: Commit the current Native Ready configuration
The Host MUST invoke the current Native Order of Battle ExecuteBeginMission command when its Ready control is enabled; when the original Ready callback is not bound after Native Auto Deploy, it MUST preserve formation configuration through ExecuteBeginMission and dispatch only that ViewModel's original Native callback target. A direct call to DeploymentHandler.FinishDeployment MUST NOT be treated as equivalent.

#### Scenario: Ready is enabled for the active field deployment
- **GIVEN** the current Mission is an eligible ordinary field battle in Deployment mode and the Native Ready control is enabled
- **WHEN** the Host submits the current Native Ready command
- **THEN** the original Native Order of Battle Ready command commits the current formation configuration and triggers the Native deployment-finish callback once

#### Scenario: Ready callback is absent after Native Auto Deploy
- **GIVEN** the current Order of Battle ViewModel has no Ready delegate after Native Auto Deploy and the Native player-side deployment handler is available
- **WHEN** the Host submits Ready
- **THEN** it calls ExecuteBeginMission to save current configuration, dispatches the original callback target once, and verifies the resulting Native Battle state
- **AND** if the callback throws after the state changes, it applies the state-verified exception rule and does not replay the command

#### Scenario: Ready is disabled or the current Native UI is unavailable
- **GIVEN** the current Native Ready control is disabled or the current ViewModel cannot be resolved
- **WHEN** the Host submits the deployment-finish action
- **THEN** the bridge rejects without directly calling DeploymentHandler.FinishDeployment, changing Campaign time, or retrying the action

#### Scenario: Ready callback error does not produce a Battle transition
- **GIVEN** a Native Ready handler returns an error but fresh state remains in Deployment or the Campaign clock did not remain Stop
- **WHEN** the Host reconciles the command result
- **THEN** it returns an unresolved setup result and does not repeat Ready, Auto Deploy, F6, or the model decision
