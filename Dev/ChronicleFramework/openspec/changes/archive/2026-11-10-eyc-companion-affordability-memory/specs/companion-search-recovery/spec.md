# Spec Delta

## ADDED Requirements

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
