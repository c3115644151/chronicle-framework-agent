# companion-search-recovery Specification

## Purpose

Keeps the MainHero agent's original Companion search and settlement movement coherent when the current Tavern has no recruitable Wanderer or a hostile Bandit interrupts travel. The memory and recovery remain bound to the same Native Campaign and original EYC Journal.

## Requirements

### Requirement: Remember a verified empty Tavern for the current EYC progress state
The Host MUST record a Town as currently lacking a recruitable Companion only after a fresh Native scene scan returns no eligible friendly Wanderer, and MUST persist that record only after returning to the original Campaign Map in the same saved Campaign.

#### Scenario: Tavern has no eligible Wanderer
- **GIVEN** the Companion objective is active and the current friendly Tavern Mission has no conversation open
- **WHEN** the Native scene scan returns no eligible Wanderer Hero
- **THEN** the Host uses the only current Native leave action, waits for MapState, and stores the Town ID in the Campaign checkpoint.

#### Scenario: Resume after a Host restart
- **GIVEN** the same Native Campaign save contains a verified empty-Tavern record matching the current EYC Journal progress
- **WHEN** the Companion route resumes and queries safe Town targets
- **THEN** it excludes the remembered Town and keeps other currently safe, unvisited Towns available.

### Requirement: Preserve empty-Tavern memory across resource loss
The Host MUST keep verified empty-Tavern records when an EYC objective's current resource value decreases, and MUST invalidate them when an objective value advances or its target changes.

#### Scenario: Ransom lowers Gold
- **GIVEN** the agent has recorded empty Taverns for the current EYC Journal snapshot
- **WHEN** original captivity recovery pays a ransom and the Gold objective value decreases
- **THEN** the Host updates the saved Journal baseline without revisiting the previously empty Towns.

#### Scenario: EYC objective advances
- **GIVEN** empty-Tavern records are tied to an earlier EYC objective snapshot
- **WHEN** a fresh Native Journal shows an objective has advanced or a dynamic target has changed
- **THEN** the Host clears the old empty-Tavern exclusions before planning the next Companion search.

### Requirement: Continue an existing Native settlement movement without reissuing it
When a child route resumes while Native MapState already shows MainParty moving toward a Settlement with the original `GoToSettlement` behavior, the Host MUST inherit that target and MUST NOT query or submit a duplicate settlement Move before the current movement resolves or is interrupted.

#### Scenario: Companion route resumes during travel
- **GIVEN** Native MapState shows an active settlement target and MainParty is moving to it
- **WHEN** the EYC parent restarts the Companion child after another event
- **THEN** the Host observes the current Native movement and waits for its arrival or a new Native event without submitting the same Move again.

### Requirement: Resolve a monitor-confirmed hostile Bandit interruption first
When the movement monitor pauses Native settlement travel because it sees a hostile Bandit, the EYC parent MUST route that current Native state to the existing BattleSimulation flow before generic paused-move recovery.

#### Scenario: Hostile Bandit appears during settlement travel
- **GIVEN** the Native movement monitor reports a visible hostile Bandit and a fresh EYC MapState remains active
- **WHEN** a child route returns that specific interruption
- **THEN** the parent evaluates the current Native encounter through the existing BattleSimulation flow and does not repeat Companion selection or the interrupted settlement Move first.

#### Scenario: Native cannot send troops
- **GIVEN** the current Native encounter offers no usable Send Troops action because MainParty has no soldiers
- **WHEN** the model chooses the current original surrender option and then accepts the visible ransom inquiry
- **THEN** the Host verifies original captivity recovery and a fresh MapState without claiming a battle win or Renown progress.

### Requirement: Reconcile Native Tavern scene observations after navigation
The Host MUST compare the current observed Wanderer distance and Native conversation-action eligibility with the prior completed navigation attempt whenever it obtains a fresh Tavern scene observation, including an automatic observation.

#### Scenario: Native navigation measurably approaches a Wanderer
- **GIVEN** the MainAgent completed Native navigation toward a currently observed friendly Wanderer
- **WHEN** a fresh scene scan shows the distance decreased by at least the configured measurable-progress threshold
- **THEN** the Host MUST clear the no-progress counter and keep that current Wanderer eligible for the next Native interaction decision.

#### Scenario: Repeated Native navigation does not approach the target
- **GIVEN** the MainAgent completed Native navigation toward the same currently observed Wanderer twice
- **AND** each fresh scene scan shows less than the measurable-progress threshold and Native conversation action remains unavailable
- **WHEN** the Host builds the next Companion action catalog
- **THEN** it MUST temporarily exclude that Wanderer for the current search and present another currently eligible candidate or the original Native Leave action, without submitting another navigation to the excluded target.

#### Scenario: Automatic scene scan reconciles navigation progress
- **GIVEN** the Companion loop performs a Native `missionSceneAgents` query itself after a completed navigation
- **WHEN** the returned scene data contains the selected Wanderer's current distance and the current state contains Native interaction eligibility
- **THEN** the Host MUST apply the same progress/stall policy used for an explicit scene-query action before constructing the next model request.

### Requirement: Record a Native no-pay response for its current Wanderer
The Host MUST record the current Wanderer Hero ID and MainHero Gold only after the original `player_companion_hire_response_2` Native option succeeds for that Hero's active Companion conversation.

#### Scenario: Native refusal records the current candidate and Gold
- **GIVEN** the Native hiring conversation for Wanderer A offers only `player_companion_hire_response_2`
- **WHEN** the Host successfully submits that Native response while MainHero has 64 Gold
- **THEN** the saved observation identifies Wanderer A and Gold 64 without recording any other candidate

#### Scenario: No Native no-pay response was selected
- **GIVEN** a candidate's price is unknown or the current Native conversation does not expose `player_companion_hire_response_2`
- **WHEN** the Host updates Companion search memory
- **THEN** it does not record that candidate as unaffordable

### Requirement: Suppress only the same unaffordable Wanderer until funds rise
The Host MUST omit a recorded Wanderer from the current Companion interaction candidates while MainHero Gold is less than or equal to that observation's Gold value. Progress in another EYC objective MUST NOT clear this candidate record. Gold above the recorded value makes that Hero eligible for a fresh Native conversation check.

#### Scenario: PartySize advances but the Wanderer remains unaffordable
- **GIVEN** Wanderer A was recorded at Gold 64 and another EYC objective later advances
- **AND** fresh MainHero Gold remains 64 or decreases
- **WHEN** a new Tavern scan lists Wanderer A and Wanderer B
- **THEN** the Host omits A and keeps B eligible without reopening A's conversation

#### Scenario: Player Gold rises after an unaffordable response
- **GIVEN** Wanderer A was recorded as unaffordable at Gold 64
- **WHEN** fresh Native state reports Gold greater than 64
- **THEN** the Host permits a fresh interaction with A and lets current Native dialogue decide whether the player can hire A
