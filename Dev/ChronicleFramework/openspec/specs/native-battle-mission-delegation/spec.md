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
The Agent MUST continue to observe and control the MainHero after troop delegation; it MUST NOT report battle success until the original Mission and its Native aftermath finish and the Campaign result is read.

#### Scenario: Troops delegated while the MainHero remains under Agent control
- **GIVEN** the original Delegate Command has changed one or more Formations to AI control
- **WHEN** the Battle Mission is still active
- **THEN** the Agent retains the MainHero as its player-controlled body and reports the Mission as ongoing, not won or resolved

#### Scenario: Native battle result returned
- **GIVEN** the original battle Mission has ended and the game entered its Native aftermath or Campaign Map state
- **WHEN** the Agent reads the resulting Native state
- **THEN** it reports the verified Native outcome and current Roster/Journal changes only after observing them

### Requirement: Use the original Attack Mission only as the no-Send-Troops fallback
When the current hostile Bandit Encounter has Native `str_order_attack` disabled but exposes the original enabled `attack` option and the current MainParty has healthy troops, the Host MAY enter the original Battle Mission only to immediately delegate its current player Formations to Native AI and passively observe the Mission. It MUST keep Native Leave and Try-to-get-away choices available, MUST NOT issue Campaign clock commands, and MUST NOT send per-frame model requests.

#### Scenario: Send Troops is available
- **GIVEN** the current Native Encounter enables `str_order_attack`
- **WHEN** the model chooses a combat action
- **THEN** the Host exposes the Native Send Troops path and does not expose `attack` as a real-time Mission alternative

#### Scenario: Send Troops is disabled and healthy MainParty troops remain
- **GIVEN** the current Native Encounter disables `str_order_attack`, enables `attack`, and the current MainParty reports at least one healthy member
- **WHEN** the model chooses the current Native `attack` option
- **THEN** the Host enters the original Campaign Battle Mission, issues Delegate Command once after Mission Mode is Battle, retains MainHero as Player-controlled, and passively observes the original result and aftermath

#### Scenario: Send Troops is disabled and no healthy troops remain
- **GIVEN** the current Native Encounter disables `str_order_attack` and the current MainParty has no healthy members
- **WHEN** the model is offered encounter actions
- **THEN** the Host does not expose the real-time `attack` option and leaves only currently enabled Native exit/survival choices

### Requirement: Finish the current Native field deployment before troop delegation
After the original Campaign Attack option enters a supported field Battle Mission in Deployment mode, the Host MUST complete Native deployment through the current field-deployment handler, verify the same Mission reaches Battle mode, and only then issue the existing F6-equivalent troop delegation once. The Host MUST NOT call the model during this transition or change Campaign time.

#### Scenario: Native field deployment advances to Battle
- **GIVEN** the current Mission is an active hostile Campaign field battle in Deployment mode, MainHero may not yet be spawned, and no Inquiry is open
- **WHEN** the bounded Native deployment-finish operation completes
- **THEN** the Host observes the same Mission in Battle mode before issuing troop delegation, keeps Campaign time stopped, and does not request another model decision during the transition

#### Scenario: Deployment cannot safely finish
- **GIVEN** the current Mission is not an eligible Campaign field battle, is already ended, has an active Inquiry, or the Native Order of Battle Ready control is unavailable
- **WHEN** the Host attempts to finish deployment
- **THEN** it rejects or stops without issuing troop delegation, changing Campaign time, or claiming a battle result

#### Scenario: Native deployment finish is rejected or ambiguous
- **GIVEN** the original Native deployment-finish operation was submitted
- **WHEN** the handler rejects it, times out, or the same Mission fails to reach Battle mode within the bounded observation window
- **THEN** the Host does not repeat the non-idempotent operation, does not send F6, and returns an explicit unresolved transition result

### Requirement: Commit the current Native Ready configuration
The Host MUST invoke the current Native Order of Battle `ExecuteBeginMission` command only when its Ready control is enabled. This preserves the original deployment configuration and callback chain; a direct call that skips the current view-model command MUST NOT be treated as equivalent.

#### Scenario: Ready is enabled for the active field deployment
- **GIVEN** the current Mission is an eligible ordinary field battle in Deployment mode and the Native Ready control is enabled
- **WHEN** the Host submits the deployment-finish action
- **THEN** the original Native Order of Battle Ready command commits the current formation configuration and triggers the Native deployment-finish callback once

#### Scenario: Ready is disabled or the current Native UI is unavailable
- **GIVEN** the current Native Ready control is disabled, its current ViewModel cannot be resolved, or a modal is active
- **WHEN** the Host submits the deployment-finish action
- **THEN** the bridge rejects without directly calling `DeploymentHandler.FinishDeployment`, changing Campaign time, or retrying the action
