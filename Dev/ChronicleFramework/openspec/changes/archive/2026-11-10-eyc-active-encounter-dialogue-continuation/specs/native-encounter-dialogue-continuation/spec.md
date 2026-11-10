# Spec Delta

## Purpose

Lets the autonomous StoryMode agent advance a forced, text-only line in a Native map encounter so the original encounter can present its real choices.

## ADDED Requirements

### Requirement: Advance only a current no-choice Native map encounter line
The Host MUST call the original Native `dialogueContinue` handler only when the current state is `MapState`, a Native map conversation has visible non-empty text, and its current option list contains no clickable answer. This rule also applies when a hostile Party encounter is active. It MUST NOT submit a fight, barter, surrender, leave, or other conversation choice during Continue.

#### Scenario: Bandit threat line has only a Continue prompt
- **GIVEN** Native MapState has an active Bandit encounter and the current conversation has visible text with no clickable options
- **WHEN** the BattleSimulation flow resolves the current encounter conversation
- **THEN** the Host advances exactly the original Native Continue handler, rereads Native state, and does not issue a clock action or choose an encounter option

#### Scenario: Native choices appear after the text advances
- **GIVEN** the Host has advanced a no-choice encounter line
- **WHEN** fresh Native state exposes one or more clickable answers
- **THEN** the Host passes only those current option IDs to the model for its next choice

#### Scenario: Continue makes no progress
- **GIVEN** Native accepted `dialogueContinue`
- **WHEN** the refreshed conversation repeats the same character and exact text with no clickable choices
- **THEN** the Host stops without issuing another identical Continue or claiming the encounter was resolved

#### Scenario: Conversation leaves the supported map state
- **GIVEN** the encounter conversation is active
- **WHEN** the current Native state is not MapState, the sentence is empty, or current choices are clickable
- **THEN** the Host does not use this automatic Continue route and follows the current supported state/choice handling instead
