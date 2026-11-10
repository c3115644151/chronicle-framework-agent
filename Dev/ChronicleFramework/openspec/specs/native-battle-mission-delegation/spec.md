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
