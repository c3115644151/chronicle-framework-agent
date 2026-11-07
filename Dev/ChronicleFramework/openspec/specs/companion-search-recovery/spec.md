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
